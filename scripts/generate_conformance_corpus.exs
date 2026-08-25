alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}
alias CharterAgreementProtocol.Conformance.Corpus

root = "priv/conformance"
case_format = "charter-agreement-protocol-conformance-cases"
index_format = "charter-agreement-protocol-conformance-corpus-index"

valid = fn output -> %{"status" => "valid", "output" => output} end
invalid = fn code -> %{"status" => "invalid", "error_code" => code} end

cases = [
  %{
    "id" => "base64url-empty",
    "surface" => "base64url.decode",
    "class" => "valid",
    "input" => %{"text" => ""},
    "expect" => valid.(%{"bytes_base64url" => ""})
  },
  %{
    "id" => "base64url-exact-two-chars",
    "surface" => "base64url.decode",
    "class" => "exact_bound",
    "input" => %{"text" => "AQ"},
    "expect" => valid.(%{"bytes_base64url" => "AQ"})
  },
  %{
    "id" => "base64url-padding-rejected",
    "surface" => "base64url.decode",
    "class" => "invalid_encoding",
    "input" => %{"text" => "AQ=="},
    "expect" => invalid.("base64url_padded")
  },
  %{
    "id" => "json-empty-object",
    "surface" => "json.decode",
    "class" => "valid",
    "input" => %{"text" => "{}"},
    "expect" => valid.(%{"tag" => "object", "members" => []})
  },
  %{
    "id" => "json-array-boundary-near",
    "surface" => "json.decode",
    "class" => "boundary_near",
    "input" => %{"text" => "[1]", "limits" => %{"max_array_items" => 2}},
    "expect" => valid.(%{"tag" => "array", "items" => [%{"tag" => "integer", "value" => 1}]})
  },
  %{
    "id" => "json-byte-exact-bound",
    "surface" => "json.decode",
    "class" => "exact_bound",
    "input" => %{"text" => "null", "limits" => %{"max_bytes" => 4}},
    "expect" => valid.(%{"tag" => "null"})
  },
  %{
    "id" => "json-byte-maximum-plus-one",
    "surface" => "json.decode",
    "class" => "maximum_plus_one",
    "input" => %{"text" => "null", "limits" => %{"max_bytes" => 3}},
    "expect" => invalid.("limit_exceeded")
  },
  %{
    "id" => "json-invalid-utf8",
    "surface" => "json.decode",
    "class" => "invalid_encoding",
    "input" => %{"bytes_base64url" => "_w"},
    "expect" => invalid.("invalid_encoding")
  },
  %{
    "id" => "json-non-binary",
    "surface" => "json.decode",
    "class" => "invalid_type",
    "input" => %{"kind" => "integer", "value" => 1},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "canonical-object",
    "surface" => "canonicalization.encode",
    "class" => "valid",
    "input" => %{"tag" => "object", "members" => [["a", %{"tag" => "integer", "value" => 1}]]},
    "expect" => valid.(%{"text" => "{\"a\":1}"})
  },
  %{
    "id" => "canonical-noncharacter",
    "surface" => "canonicalization.encode",
    "class" => "invalid_encoding",
    "input" => %{"tag" => "string_codepoint", "value" => "FFFF"},
    "expect" => invalid.("invalid_encoding")
  },
  %{
    "id" => "canonical-noncanonical-member-order",
    "surface" => "canonicalization.encode",
    "class" => "non_canonical_bytes",
    "input" => %{"text" => "{\"b\":1,\"a\":2}"},
    "expect" => invalid.("non_canonical_bytes")
  },
  %{
    "id" => "canonical-improper-term",
    "surface" => "canonicalization.encode",
    "class" => "invalid_type",
    "input" => %{"kind" => "improper_object"},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "digest-domain-separated",
    "surface" => "digest.hash",
    "class" => "valid",
    "input" => %{"domain" => "charter_revision_content", "bytes_base64url" => "e30"},
    "expect" => valid.(%{"algorithm" => "sha-256"})
  },
  %{
    "id" => "digest-non-bytes",
    "surface" => "digest.hash",
    "class" => "invalid_type",
    "input" => %{"kind" => "integer", "value" => 1},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "digest-content-mismatch",
    "surface" => "digest.hash",
    "class" => "digest_mismatch",
    "input" => %{
      "domain" => "charter_revision_content",
      "bytes_base64url" => "e30",
      "tagged" => "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    "expect" => invalid.("digest_mismatch")
  },
  %{
    "id" => "schema-valid-object",
    "surface" => "schema.validate",
    "class" => "valid",
    "input" => %{"members" => %{"name" => "ok"}},
    "expect" => valid.(%{"members" => %{"name" => "ok"}})
  },
  %{
    "id" => "schema-wrong-type",
    "surface" => "schema.validate",
    "class" => "invalid_type",
    "input" => %{"members" => %{"name" => 1}},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "schema-constraint",
    "surface" => "schema.validate",
    "class" => "invalid_constraint",
    "input" => %{"members" => %{"name" => "!"}},
    "expect" => invalid.("constraint_violation")
  },
  %{
    "id" => "schema-cardinality",
    "surface" => "schema.validate",
    "class" => "invalid_cardinality",
    "input" => %{"members" => %{"name" => "a"}},
    "expect" => invalid.("cardinality_violation")
  },
  %{
    "id" => "schema-unknown-member",
    "surface" => "schema.validate",
    "class" => "unknown_member",
    "input" => %{"members" => %{"name" => "ok", "rogue" => true}},
    "expect" => invalid.("unknown_member")
  },
  %{
    "id" => "schema-missing-required",
    "surface" => "schema.validate",
    "class" => "missing_required",
    "input" => %{"members" => %{}},
    "expect" => invalid.("missing_required")
  },
  %{
    "id" => "schema-maximum-plus-one",
    "surface" => "schema.validate",
    "class" => "maximum_plus_one",
    "input" => %{"members" => %{"name" => "abcde"}},
    "expect" => invalid.("cardinality_violation")
  }
]

tagged = fn plain ->
  recur = fn
    _recur, nil ->
      :null

    _recur, value when is_boolean(value) ->
      {:boolean, value}

    _recur, value when is_integer(value) ->
      {:integer, value}

    _recur, value when is_float(value) ->
      {:float, value}

    _recur, value when is_binary(value) ->
      {:string, value}

    recur, value when is_list(value) ->
      {:array, Enum.map(value, &recur.(recur, &1))}

    recur, value when is_map(value) ->
      {:object, Enum.map(value, fn {key, item} -> {key, recur.(recur, item)} end)}
  end

  recur.(recur, plain)
end

canonical = fn value ->
  {:ok, bytes} = Canonicalization.encode(tagged.(value))
  bytes
end

descriptor_key = fn byte, key_id ->
  {public, private} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))

  {%{
     "key_id" => key_id,
     "algorithm" => "Ed25519",
     "public_key" => Base64Url.encode(public),
     "status" => "active"
   }, private}
end

descriptor_compact = fn claims, kid, private ->
  protected = canonical.(%{"alg" => "EdDSA", "kid" => kid, "typ" => "cap+party"})
  payload = canonical.(claims)
  protected_segment = Base64Url.encode(protected)
  payload_segment = Base64Url.encode(payload)
  message = protected_segment <> "." <> payload_segment
  signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])

  %{
    compact: message <> "." <> Base64Url.encode(signature),
    digest: :party_descriptor_content |> Digest.hash(payload) |> Digest.to_tagged()
  }
end

{genesis_key, genesis_private} = descriptor_key.(1, "genesis-key")
{_wrong_key, wrong_private} = descriptor_key.(9, "wrong-key")

genesis_claims = %{
  "protocol_revision" => 1,
  "descriptor_number" => 1,
  "verification_keys" => [genesis_key],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-08-25T10:00:00Z"
}

genesis =
  descriptor_compact.(
    genesis_claims,
    "genesis-key",
    genesis_private
  )

wrong_signed_genesis = descriptor_compact.(genesis_claims, "genesis-key", wrong_private)

successor = fn byte, key_id, signing_private, previous_digest ->
  {key, _private} = descriptor_key.(byte, key_id)

  descriptor_compact.(
    %{
      "protocol_revision" => 1,
      "party_id" => genesis.digest,
      "descriptor_number" => 2,
      "prev_descriptor_digest" => previous_digest,
      "verification_keys" => [key],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:01Z"
    },
    "genesis-key",
    signing_private
  )
end

left = successor.(2, "left-key", genesis_private, genesis.digest)
right = successor.(3, "right-key", genesis_private, genesis.digest)
wrong_signed_child = successor.(4, "wrong-signed-key", wrong_private, genesis.digest)

orphan =
  successor.(
    5,
    "orphan-key",
    genesis_private,
    "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  )

descriptor_cases = [
  %{
    "id" => "party-descriptor-genesis-valid",
    "surface" => "party_descriptor.verify",
    "class" => "valid",
    "input" => %{"compact" => genesis.compact, "predecessor" => nil},
    "expect" =>
      valid.(%{
        "descriptor_digest" => genesis.digest,
        "party_id" => genesis.digest,
        "descriptor_number" => 1
      })
  },
  %{
    "id" => "party-descriptor-wrong-signature",
    "surface" => "party_descriptor.verify",
    "class" => "signature_invalid",
    "input" => %{"compact" => wrong_signed_genesis.compact, "predecessor" => nil},
    "expect" => invalid.("signature_invalid")
  },
  %{
    "id" => "descriptor-chain-superseded-position",
    "surface" => "descriptor_chain.verify",
    "class" => "descriptor_superseded",
    "input" => %{"compacts" => [genesis.compact, left.compact]},
    "expect" =>
      valid.(%{
        "topology" => "linear",
        "positions" => %{
          genesis.digest => "superseded",
          left.digest => "head"
        }
      })
  },
  %{
    "id" => "descriptor-chain-signed-sibling-fork",
    "surface" => "descriptor_chain.verify",
    "class" => "descriptor_fork",
    "input" => %{"compacts" => [genesis.compact, left.compact, right.compact]},
    "expect" =>
      valid.(%{
        "topology" => "forked",
        "sibling_descriptors" => Enum.sort([left.digest, right.digest])
      })
  },
  %{
    "id" => "descriptor-chain-wrong-signer",
    "surface" => "descriptor_chain.verify",
    "class" => "signature_invalid",
    "input" => %{"compacts" => [genesis.compact, wrong_signed_child.compact]},
    "expect" => invalid.("descriptor_chain_invalid")
  },
  %{
    "id" => "descriptor-chain-orphan",
    "surface" => "descriptor_chain.verify",
    "class" => "chain_invalid",
    "input" => %{"compacts" => [genesis.compact, orphan.compact]},
    "expect" => invalid.("descriptor_chain_invalid")
  }
]

legal_text = "Example charter terms\n"

revision_claims = %{
  "protocol_revision" => 1,
  "revision_number" => 1,
  "parties" => [
    %{"party_descriptor_digest" => genesis.digest, "role" => "issuer"},
    %{
      "party_descriptor_digest" =>
        :party_descriptor_content |> Digest.hash("party:acceptor") |> Digest.to_tagged(),
      "role" => "acceptor"
    }
  ],
  "legal_text" => %{
    "content_digest" => :legal_text |> Digest.hash(legal_text) |> Digest.to_tagged(),
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
      "deployment_digest" => "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"
    }
  ],
  "receipt_profile" => "com.example.charter/default",
  "extensions" => %{"critical" => %{}, "optional" => %{}}
}

revision_bytes = canonical.(revision_claims)
revision_digest = :charter_revision_content |> Digest.hash(revision_bytes) |> Digest.to_tagged()

revision_case = fn id, class, claims, expectation ->
  %{
    "id" => id,
    "surface" => "charter_revision.decode",
    "class" => class,
    "input" => %{"text" => canonical.(claims)},
    "expect" => expectation
  }
end

revision_cases = [
  revision_case.(
    "charter-revision-genesis-valid",
    "valid",
    revision_claims,
    valid.(%{
      "revision_digest" => revision_digest,
      "revision_number" => 1,
      "precedence_declaration" => "legal_text_governs",
      "abp_binding" => %{
        "blueprint_id" => "example.demo/echo",
        "release_number" => 1,
        "content_digest" => "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
        "deployment_digest" => "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"
      }
    })
  ),
  revision_case.(
    "charter-revision-duplicate-role",
    "invalid_constraint",
    put_in(revision_claims, ["parties", Access.at(1), "role"], "issuer"),
    invalid.("revision_invalid")
  ),
  revision_case.(
    "charter-revision-genesis-supersession",
    "invalid_constraint",
    Map.put(revision_claims, "supersedes", [revision_digest]),
    invalid.("revision_invalid")
  ),
  revision_case.(
    "charter-revision-non-string-supersession",
    "invalid_type",
    Map.put(revision_claims, "supersedes", [42])
    |> Map.merge(%{
      "charter_id" => revision_digest,
      "revision_number" => 2,
      "prev_revision_digest" => revision_digest
    }),
    invalid.("revision_invalid")
  ),
  revision_case.(
    "charter-revision-empty-reasons",
    "invalid_cardinality",
    put_in(revision_claims, ["termination_rules", "reason_codes"], []),
    invalid.("nested_invalid")
  ),
  revision_case.(
    "charter-revision-unknown-member",
    "unknown_member",
    Map.put(revision_claims, "unexpected", true),
    invalid.("unknown_member")
  ),
  revision_case.(
    "charter-revision-missing-precedence",
    "missing_required",
    Map.delete(revision_claims, "precedence_declaration"),
    invalid.("missing_required")
  )
]

acceptance_compact = fn claims, kid, private ->
  protected = canonical.(%{"alg" => "EdDSA", "kid" => kid, "typ" => "cap+acceptance"})
  payload = canonical.(claims)
  protected_segment = Base64Url.encode(protected)
  payload_segment = Base64Url.encode(payload)
  message = protected_segment <> "." <> payload_segment
  signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])

  %{
    compact: message <> "." <> Base64Url.encode(signature),
    digest: :acceptance_content |> Digest.hash(payload) |> Digest.to_tagged()
  }
end

acceptance_claims = fn revision, content_digest ->
  base = %{
    "protocol_revision" => 1,
    "charter_id" => revision["charter_id"] || content_digest,
    "revision_number" => revision["revision_number"],
    "revision_digest" => content_digest,
    "party_descriptor_digest" => genesis.digest,
    "party_role" => "issuer",
    "accepted_at" => "2026-08-25T13:00:00Z"
  }

  if revision["revision_number"] == 1,
    do: base,
    else: Map.put(base, "prev_revision_digest", revision["prev_revision_digest"])
end

acceptance_claims_value = acceptance_claims.(revision_claims, revision_digest)

acceptance =
  acceptance_compact.(acceptance_claims_value, "genesis-key", genesis_private)

mismatched_acceptance =
  acceptance_claims_value
  |> Map.put("revision_digest", "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
  |> acceptance_compact.("genesis-key", genesis_private)

wrong_signed_acceptance =
  acceptance_compact.(acceptance_claims_value, "genesis-key", wrong_private)

successor_revision = fn legal ->
  revision_claims
  |> Map.merge(%{
    "charter_id" => revision_digest,
    "revision_number" => 2,
    "prev_revision_digest" => revision_digest,
    "effective_from" => "2026-08-25T12:00:01Z",
    "legal_text" => %{
      "content_digest" => :legal_text |> Digest.hash(legal) |> Digest.to_tagged(),
      "media_type" => "text/plain"
    }
  })
end

left_revision = successor_revision.("left terms\n")
right_revision = successor_revision.("right terms\n")
left_revision_bytes = canonical.(left_revision)
right_revision_bytes = canonical.(right_revision)

left_revision_digest =
  :charter_revision_content |> Digest.hash(left_revision_bytes) |> Digest.to_tagged()

right_revision_digest =
  :charter_revision_content |> Digest.hash(right_revision_bytes) |> Digest.to_tagged()

left_acceptance =
  left_revision
  |> acceptance_claims.(left_revision_digest)
  |> acceptance_compact.("genesis-key", genesis_private)

right_acceptance =
  right_revision
  |> acceptance_claims.(right_revision_digest)
  |> acceptance_compact.("genesis-key", genesis_private)

acceptance_cases = [
  %{
    "id" => "acceptance-valid",
    "surface" => "acceptance.verify",
    "class" => "valid",
    "input" => %{
      "compact" => acceptance.compact,
      "revision_text" => revision_bytes,
      "descriptor_compacts" => [genesis.compact]
    },
    "expect" =>
      valid.(%{
        "acceptance_digest" => acceptance.digest,
        "revision_digest" => revision_digest,
        "party_descriptor_digest" => genesis.digest,
        "descriptor_position" => "head"
      })
  },
  %{
    "id" => "acceptance-claim-mismatch",
    "surface" => "acceptance.verify",
    "class" => "invalid_constraint",
    "input" => %{
      "compact" => mismatched_acceptance.compact,
      "revision_text" => revision_bytes,
      "descriptor_compacts" => [genesis.compact]
    },
    "expect" => invalid.("acceptance_claims_mismatch")
  },
  %{
    "id" => "acceptance-wrong-signature",
    "surface" => "acceptance.verify",
    "class" => "signature_invalid",
    "input" => %{
      "compact" => wrong_signed_acceptance.compact,
      "revision_text" => revision_bytes,
      "descriptor_compacts" => [genesis.compact]
    },
    "expect" => invalid.("signature_invalid")
  },
  %{
    "id" => "acceptance-same-signer-equivocation",
    "surface" => "acceptance.equivocation",
    "class" => "equivocation",
    "input" => %{
      "descriptor_compacts" => [genesis.compact],
      "signed_revisions" => [
        %{"compact" => left_acceptance.compact, "revision_text" => left_revision_bytes},
        %{"compact" => right_acceptance.compact, "revision_text" => right_revision_bytes}
      ]
    },
    "expect" =>
      valid.(%{
        "kind" => "acceptance_equivocation",
        "revision_number" => 2,
        "revision_digests" => Enum.sort([left_revision_digest, right_revision_digest]),
        "winner" => nil
      })
  }
]

termination_compact = fn claims, kid, private ->
  protected = canonical.(%{"alg" => "EdDSA", "kid" => kid, "typ" => "cap+termination"})
  payload = canonical.(claims)
  protected_segment = Base64Url.encode(protected)
  payload_segment = Base64Url.encode(payload)
  message = protected_segment <> "." <> payload_segment
  signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])

  %{
    compact: message <> "." <> Base64Url.encode(signature),
    digest: :termination_content |> Digest.hash(payload) |> Digest.to_tagged()
  }
end

termination_claims = %{
  "protocol_revision" => 1,
  "charter_id" => revision_digest,
  "governing_revision_digest" => revision_digest,
  "party_descriptor_digest" => genesis.digest,
  "party_role" => "issuer",
  "reason_code" => "mutual",
  "effective_at" => "2026-08-26T13:00:00Z",
  "issued_at" => "2026-08-25T13:00:00Z"
}

termination = termination_compact.(termination_claims, "genesis-key", genesis_private)

unlisted_termination =
  termination_claims
  |> Map.put("reason_code", "not-listed")
  |> termination_compact.("genesis-key", genesis_private)

late_termination =
  termination_claims
  |> Map.put("issued_at", "2026-08-26T13:00:01Z")
  |> termination_compact.("genesis-key", genesis_private)

wrong_signed_termination =
  termination_compact.(termination_claims, "genesis-key", wrong_private)

termination_input = fn compact ->
  %{
    "compact" => compact,
    "revision_text" => revision_bytes,
    "descriptor_compacts" => [genesis.compact]
  }
end

termination_cases = [
  %{
    "id" => "termination-valid",
    "surface" => "termination.verify",
    "class" => "valid",
    "input" => termination_input.(termination.compact),
    "expect" =>
      valid.(%{
        "termination_digest" => termination.digest,
        "governing_revision_digest" => revision_digest,
        "party_descriptor_digest" => genesis.digest,
        "reason_code" => "mutual",
        "descriptor_position" => "head"
      })
  },
  %{
    "id" => "termination-unlisted-reason",
    "surface" => "termination.verify",
    "class" => "invalid_constraint",
    "input" => termination_input.(unlisted_termination.compact),
    "expect" => invalid.("termination_claims_mismatch")
  },
  %{
    "id" => "termination-issued-after-effective",
    "surface" => "termination.verify",
    "class" => "invalid_constraint",
    "input" => termination_input.(late_termination.compact),
    "expect" => invalid.("termination_invalid")
  },
  %{
    "id" => "termination-wrong-signature",
    "surface" => "termination.verify",
    "class" => "signature_invalid",
    "input" => termination_input.(wrong_signed_termination.compact),
    "expect" => invalid.("signature_invalid")
  }
]

cases = cases ++ descriptor_cases ++ revision_cases ++ acceptance_cases ++ termination_cases

raw_hash = fn bytes -> bytes |> Digest.of() |> Map.fetch!(:bytes) |> Base64Url.encode() end

grouped = Enum.group_by(cases, & &1["surface"])

files =
  Enum.map(Corpus.surfaces(), fn surface ->
    path = "cases/" <> String.replace(surface, ".", "-") <> ".json"
    surface_cases = Map.fetch!(grouped, surface)
    bytes = canonical.(%{"format" => case_format, "cases" => surface_cases})
    target = Path.join(root, path)
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, bytes)

    %{"path" => path, "sha256_base64url" => raw_hash.(bytes), "cases" => length(surface_cases)}
  end)

observed = Enum.frequencies_by(cases, &{&1["surface"], &1["class"]})

applicability =
  Map.new(Corpus.surfaces(), fn surface ->
    floor = Map.fetch!(Corpus.floor(), surface)

    cells =
      Map.new(Corpus.classes(), fn class ->
        if class in floor.required,
          do: {class, Map.get(observed, {surface, class}, 0)},
          else: {class, %{"n_a" => floor.n_a}}
      end)

    {surface, cells}
  end)

index = %{
  "format" => index_format,
  "corpus_digest" => "",
  "total_cases" => length(cases),
  "files" => files,
  "applicability" => applicability
}

index_without_digest = Map.delete(index, "corpus_digest")

identity =
  index_without_digest
  |> canonical.()
  |> then(&Digest.hash(:corpus_index, &1))
  |> Digest.to_tagged()

index = Map.put(index, "corpus_digest", identity)
File.mkdir_p!(root)
File.write!(Path.join(root, "index.json"), canonical.(index))
IO.puts(identity)
