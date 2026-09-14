# One-time builder for the frozen ML-DSA-65 supplemental corpus population.
# ML-DSA signing is randomized (FIPS 204 hedged signing) and OTP keygen is not
# seedable, so these cases are generated once and frozen: the corpus generator
# reads them back from the case files by ID at every regeneration.
#
# Run: mix run --no-start scripts/build_mldsa_cases.exs

alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}

tagged_fun = fn fun, value ->
  cond do
    is_map(value) -> {:object, Enum.map(value, fn {k, v} -> {to_string(k), fun.(fun, v)} end)}
    is_list(value) -> {:array, Enum.map(value, &fun.(fun, &1))}
    is_binary(value) -> {:string, value}
    is_integer(value) -> {:integer, value}
    is_float(value) -> {:float, value}
    is_boolean(value) -> {:boolean, value}
    value === nil or value === :null -> :null
  end
end

canonical = fn value ->
  {:ok, bytes} = Canonicalization.encode(tagged_fun.(tagged_fun, value))
  bytes
end

ed_key = fn byte, kid ->
  {pub, priv} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))

  {%{
     "key_id" => kid,
     "algorithm" => "Ed25519",
     "public_key" => Base64Url.encode(pub),
     "status" => "active"
   }, priv}
end

{ml_pub, ml_priv} = :crypto.generate_key(:mldsa65, [])

ml_key = %{
  "key_id" => "mldsa-key",
  "algorithm" => "ML-DSA-65",
  "public_key" => Base64Url.encode(ml_pub),
  "status" => "active"
}

ml_sign = fn message -> :crypto.sign(:mldsa65, :none, message, ml_priv) end

# ed25519 private key material for classical signings, derived from a seed byte
ml_ed_priv = fn byte ->
  :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32)) |> elem(1)
end

descriptor_digest = fn claims ->
  claims
  |> canonical.()
  |> then(&Digest.hash(:party_descriptor_content, &1))
  |> Digest.to_tagged()
end

sign_descriptor = fn claims, kid, priv_seed, alg ->
  protected = canonical.(%{"alg" => alg, "kid" => kid, "typ" => "cap+party"})
  payload = canonical.(claims)
  message = Base64Url.encode(protected) <> "." <> Base64Url.encode(payload)

  signature =
    if alg == "ML-DSA-65",
      do: ml_sign.(message),
      else: :crypto.sign(:eddsa, :none, message, [ml_ed_priv.(priv_seed), :ed25519])

  message <> "." <> Base64Url.encode(signature)
end

# --- Fixtures -------------------------------------------------------------

{old_key, _old_priv} = ed_key.(1, "bridge-key")

pq_claims = %{
  "protocol_revision" => 3,
  "descriptor_number" => 1,
  "verification_keys" => [ml_key],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-08-25T10:00:00Z"
}

pq_descriptor = sign_descriptor.(pq_claims, "mldsa-key", nil, "ML-DSA-65")
pq_digest = descriptor_digest.(pq_claims)

# (ML-DSA-65, revision 2) — the per-name binding negative
pq_rev2_rejected =
  sign_descriptor.(Map.put(pq_claims, "protocol_revision", 2), "mldsa-key", nil, "ML-DSA-65")

# An ML-DSA key declared inside a revision-2 descriptor — the key-grammar gate
{short_ed_pub, short_ed_priv_value} =
  :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<5>>, 32))

key_in_rev2_claims = %{
  "protocol_revision" => 2,
  "descriptor_number" => 1,
  "verification_keys" => [
    %{
      "key_id" => "bridge-key",
      "algorithm" => "Ed25519",
      "public_key" => Base64Url.encode(short_ed_pub),
      "status" => "active"
    },
    ml_key
  ],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-08-25T10:00:00Z"
}

key_in_rev2 = sign_descriptor.(key_in_rev2_claims, "bridge-key", 5, "Ed25519")

# Wrong-length ML-DSA key (1951 bytes) in a revision-3 descriptor
ml_pub_short = binary_part(ml_pub, 0, 1951)

short_key_claims =
  Map.put(pq_claims, "verification_keys", [
    %{
      "key_id" => "mldsa-key",
      "algorithm" => "ML-DSA-65",
      "public_key" => Base64Url.encode(ml_pub_short),
      "status" => "active"
    }
  ])

short_key_descriptor = sign_descriptor.(short_key_claims, "mldsa-key", nil, "ML-DSA-65")

# Truncated signature (signature-length mismatch at the framing layer)
[p, payload_seg, _sig] = String.split(pq_descriptor, ".")
{:ok, real_sig} = Base64Url.decode(String.split(pq_descriptor, ".") |> Enum.at(2))
truncated = p <> "." <> payload_seg <> "." <> Base64Url.encode(binary_part(real_sig, 0, 3308))

# Bridge chain: genesis (Ed25519, revision 2) -> successor (revision 3)
# declaring both keys, signed by the predecessor's Ed25519 key
bridge_genesis_claims = %{
  "protocol_revision" => 2,
  "descriptor_number" => 1,
  "verification_keys" => [old_key],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-08-25T10:00:00Z"
}

bridge_genesis = sign_descriptor.(bridge_genesis_claims, "bridge-key", 1, "Ed25519")
bridge_genesis_digest = descriptor_digest.(bridge_genesis_claims)

bridge_successor_claims = %{
  "protocol_revision" => 3,
  "party_id" => bridge_genesis_digest,
  "descriptor_number" => 2,
  "prev_descriptor_digest" => bridge_genesis_digest,
  "verification_keys" => [old_key, ml_key],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-08-25T10:00:01Z"
}

bridge_successor = sign_descriptor.(bridge_successor_claims, "bridge-key", 1, "Ed25519")
bridge_head_digest = descriptor_digest.(bridge_successor_claims)

{acceptor_key, acceptor_seed} = ed_key.(7, "acceptor-key")
{_, acceptor_priv} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<7>>, 32))

acceptor_claims = %{
  "protocol_revision" => 1,
  "descriptor_number" => 1,
  "verification_keys" => [acceptor_key],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-08-25T10:00:00Z"
}

acceptor_descriptor = sign_descriptor.(acceptor_claims, "acceptor-key", 7, "EdDSA")
acceptor_digest = descriptor_digest.(acceptor_claims)

legal = "terms\n"
deployment = "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"

revision_at = fn protocol_revision, issuer_digest ->
  %{
    "protocol_revision" => protocol_revision,
    "revision_number" => 1,
    "parties" => [
      %{"party_descriptor_digest" => issuer_digest, "role" => "issuer"},
      %{"party_descriptor_digest" => acceptor_digest, "role" => "acceptor"}
    ],
    "legal_text" => %{
      "content_digest" => Digest.hash(:legal_text, legal) |> Digest.to_tagged(),
      "media_type" => "text/plain",
      "uri_hint" => "https://example.com/charter.txt"
    },
    "precedence_declaration" => "legal_text_governs",
    "attribution_declaration" => %{"basis" => "bound_deployments"},
    "effective_from" => "2026-08-25T12:00:00Z",
    "termination_rules" => %{"reason_codes" => ["mutual", "breach"]},
    "abp_bindings" => [
      %{
        "party_role" => "issuer",
        "blueprint_id" => "example.demo/echo",
        "release_number" => 1,
        "content_digest" => "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
        "deployment_digest" => deployment
      }
    ],
    "receipt_profile" => "com.example.charter/default",
    "extensions" => %{"critical" => %{}, "optional" => %{}}
  }
end

mixed_revision_claims = revision_at.(2, pq_digest)
mixed_revision_bytes = canonical.(mixed_revision_claims)

mixed_revision_digest =
  Digest.hash(:charter_revision_content, mixed_revision_bytes) |> Digest.to_tagged()

bridge_revision_claims = revision_at.(2, bridge_head_digest)
bridge_revision_bytes = canonical.(bridge_revision_claims)

bridge_revision_digest =
  Digest.hash(:charter_revision_content, bridge_revision_bytes) |> Digest.to_tagged()

acceptance_compact = fn claims, kid, alg, seed_or_mldsa ->
  protected = canonical.(%{"alg" => alg, "kid" => kid, "typ" => "cap+acceptance"})
  payload = canonical.(claims)
  message = Base64Url.encode(protected) <> "." <> Base64Url.encode(payload)

  signature =
    if alg == "ML-DSA-65",
      do: ml_sign.(message),
      else: :crypto.sign(:eddsa, :none, message, [ml_ed_priv.(seed_or_mldsa), :ed25519])

  message <> "." <> Base64Url.encode(signature)
end

mixed_acceptance = fn descriptor_digest, role ->
  %{
    "protocol_revision" => if(role == "issuer", do: 3, else: 1),
    "charter_id" => mixed_revision_digest,
    "revision_number" => 1,
    "revision_digest" => mixed_revision_digest,
    "party_descriptor_digest" => descriptor_digest,
    "party_role" => role,
    "accepted_at" => "2026-08-25T13:00:00Z"
  }
end

mixed_issuer_acceptance =
  acceptance_compact.(mixed_acceptance.(pq_digest, "issuer"), "mldsa-key", "ML-DSA-65", nil)

mixed_acceptor_acceptance =
  acceptance_compact.(mixed_acceptance.(acceptor_digest, "acceptor"), "acceptor-key", "EdDSA", 7)

mixed_chain_input = %{
  "revisions" => [mixed_revision_bytes],
  "acceptances" => [mixed_issuer_acceptance, mixed_acceptor_acceptance],
  "descriptors" => [pq_descriptor, acceptor_descriptor],
  "terminations" => []
}

bridge_acceptance = fn descriptor_digest, role ->
  %{
    "protocol_revision" => if(role == "issuer", do: 2, else: 1),
    "charter_id" => bridge_revision_digest,
    "revision_number" => 1,
    "revision_digest" => bridge_revision_digest,
    "party_descriptor_digest" => descriptor_digest,
    "party_role" => role,
    "accepted_at" => "2026-08-25T13:00:00Z"
  }
end

bridge_issuer_acceptance =
  acceptance_compact.(
    bridge_acceptance.(bridge_head_digest, "issuer"),
    "bridge-key",
    "Ed25519",
    1
  )

bridge_acceptor_acceptance =
  acceptance_compact.(bridge_acceptance.(acceptor_digest, "acceptor"), "acceptor-key", "EdDSA", 7)

bridge_chain_input = %{
  "revisions" => [bridge_revision_bytes],
  "acceptances" => [bridge_issuer_acceptance, bridge_acceptor_acceptance],
  "descriptors" => [bridge_genesis, bridge_successor, acceptor_descriptor],
  "terminations" => []
}

pq_receipt_claims = %{
  "protocol_revision" => 3,
  "charter_id" => mixed_revision_digest,
  "revision_number" => 1,
  "revision_digest" => mixed_revision_digest,
  "issuing_party_role" => "issuer",
  "agent_party_role" => "issuer",
  "deployment_digest" => deployment,
  "grant" => %{
    "scheme" => "bap",
    "id" => "grant-2026-09-14-001",
    "grant_digest" => "sha-256:5k224cZ_lMI9VoUZ_fYM31ZJAcnJiht0GYEpnhes_ZI"
  },
  "invocation_id" => "123e4567-e89b-42d3-a456-426614174000",
  "decision" => "accepted",
  "outcome" => "effect_committed",
  "occurred_at" => "2026-08-25T12:00:01Z",
  "recorded_at" => "2026-08-25T12:00:02Z",
  "extensions" => %{"critical" => %{}, "optional" => %{}}
}

pq_receipt_compact =
  (fn claims ->
     protected = canonical.(%{"alg" => "ML-DSA-65", "kid" => "mldsa-key", "typ" => "cap+receipt"})
     payload = canonical.(claims)
     message = Base64Url.encode(protected) <> "." <> Base64Url.encode(payload)
     message <> "." <> Base64Url.encode(ml_sign.(message))
   end).(pq_receipt_claims)

receipt_digest =
  Digest.hash(:receipt_content, canonical.(pq_receipt_claims)) |> Digest.to_tagged()

valid = fn output -> %{"status" => "valid", "output" => output} end
invalid = fn code -> %{"status" => "invalid", "error_code" => code} end

cases = [
  %{
    "id" => "descriptor-mldsa65-rev3-valid",
    "surface" => "party_descriptor.verify",
    "class" => "valid",
    "input" => %{"compact" => pq_descriptor, "predecessor" => nil},
    "expect" =>
      valid.(%{
        "descriptor_digest" => pq_digest,
        "party_id" => pq_digest,
        "descriptor_number" => 1
      })
  },
  %{
    "id" => "descriptor-mldsa65-rev2-rejected",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => pq_rev2_rejected, "predecessor" => nil},
    "expect" => invalid.("protected_header_invalid")
  },
  %{
    "id" => "descriptor-mldsa-key-in-rev2-rejected",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => key_in_rev2, "predecessor" => nil},
    "expect" => invalid.("descriptor_invalid")
  },
  %{
    "id" => "descriptor-mldsa65-key-length-rejected",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => short_key_descriptor, "predecessor" => nil},
    "expect" => invalid.("nested_invalid")
  },
  %{
    "id" => "descriptor-mldsa65-signature-length-rejected",
    "surface" => "party_descriptor.verify",
    "class" => "signature_invalid",
    "input" => %{"compact" => truncated, "predecessor" => nil},
    "expect" => invalid.("signature_invalid")
  },
  %{
    "id" => "chain-pq-key-bridge",
    "surface" => "chain.verify",
    "class" => "valid",
    "input" => bridge_chain_input,
    "expect" =>
      valid.(%{
        "charter_id" => bridge_revision_digest,
        "topology" => "linear",
        "accepted_revision_digests" => [bridge_revision_digest],
        "superseded_revision_digests" => []
      })
  },
  %{
    "id" => "chain-mldsa-mixed-revision",
    "surface" => "chain.verify",
    "class" => "valid",
    "input" => mixed_chain_input,
    "expect" =>
      valid.(%{
        "charter_id" => mixed_revision_digest,
        "topology" => "linear",
        "accepted_revision_digests" => [mixed_revision_digest],
        "superseded_revision_digests" => []
      })
  },
  %{
    "id" => "acceptance-mldsa65-rev3-valid",
    "surface" => "acceptance.verify",
    "class" => "valid",
    "input" => %{
      "compact" => mixed_issuer_acceptance,
      "revision_text" => mixed_revision_bytes,
      "descriptor_compacts" => [pq_descriptor]
    },
    "expect" =>
      valid.(%{
        "acceptance_digest" =>
          Digest.hash(:acceptance_content, canonical.(mixed_acceptance.(pq_digest, "issuer")))
          |> Digest.to_tagged(),
        "revision_digest" => mixed_revision_digest,
        "party_descriptor_digest" => pq_digest,
        "descriptor_position" => "head"
      })
  },
  %{
    "id" => "receipt-mldsa65-rev3-valid",
    "surface" => "receipt.verify",
    "class" => "valid",
    "input" => %{"chain" => mixed_chain_input, "compact" => pq_receipt_compact},
    "expect" =>
      valid.(%{
        "receipt_digest" => receipt_digest,
        "revision_number" => 1,
        "revision_digest" => mixed_revision_digest,
        "decision" => "accepted",
        "outcome" => "effect_committed",
        "chain_conflict" => "none",
        "governing_match" => "match",
        "deployment_digest_matched" => true,
        "optional_extensions_retained" => []
      })
  }
]

# Merge into the per-surface case files (canonical rewrite).
root = "priv/conformance"

Enum.each(cases, fn case_ ->
  path = Path.join(root, "cases/" <> String.replace(case_["surface"], ".", "-") <> ".json")
  {:ok, bytes} = File.read(path)
  document = :json.decode(bytes)
  existing = Map.fetch!(document, "cases")
  ids = Enum.map(existing, & &1["id"])

  if case_["id"] in ids do
    IO.puts("already present: #{case_["id"]}")
  else
    stringify = fn
      fun, value when is_map(value) ->
        Map.new(value, fn {k, v} -> {to_string(k), fun.(fun, v)} end)

      fun, value when is_list(value) ->
        Enum.map(value, &fun.(fun, &1))

      _fun, value when value === :null ->
        nil

      _fun, value ->
        value
    end

    updated = %{
      "format" => Map.fetch!(document, "format") |> to_string(),
      "cases" => stringify.(stringify, existing) ++ [case_]
    }

    canonical_bytes = canonical.(updated)
    File.write!(path, canonical_bytes)
    IO.puts("appended: #{case_["id"]} -> #{path}")
  end
end)

IO.puts("--- frozen ML-DSA-65 public key (base64url): #{Base64Url.encode(ml_pub)}")
