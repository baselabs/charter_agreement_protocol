Code.require_file("signing_prepare_cases.exs", __DIR__)
Code.require_file("ed25519_key_cases.exs", __DIR__)

alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest, ExtensionRegistry}
alias CharterAgreementProtocol.Conformance.Corpus

root = System.get_env("CAP_CONFORMANCE_ROOT") || "priv/conformance"
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

    _recur, :null ->
      :null
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

sign_compact = fn claims, kid, private, alg, typ, digest_domain ->
  protected = canonical.(%{"alg" => alg, "kid" => kid, "typ" => typ})
  payload = canonical.(claims)
  protected_segment = Base64Url.encode(protected)
  payload_segment = Base64Url.encode(payload)
  message = protected_segment <> "." <> payload_segment
  signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])

  %{
    compact: message <> "." <> Base64Url.encode(signature),
    digest: digest_domain |> Digest.hash(payload) |> Digest.to_tagged()
  }
end

descriptor_compact = fn claims, kid, private ->
  sign_compact.(claims, kid, private, "EdDSA", "cap+party", :party_descriptor_content)
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

# The descriptor timestamp-floor witness (the release-identity act's own
# green-to-red transition): a codec-valid long-fraction spelling the 0.3.x
# codec accepted and the floor now rejects at the schema stage, exactly as
# the seven sibling timestamp members have since the resource boundary.
long_fraction_genesis =
  descriptor_compact.(
    %{
      genesis_claims
      | "effective_from" => "2026-08-25T10:00:00." <> String.duplicate("1", 60) <> "Z"
    },
    "genesis-key",
    genesis_private
  )

# --- The revision-2 alg-name population (RFC 9864; ADR
# algorithm-name-agility). The fixtures above pin revision 1 + EdDSA
# literally, ON PURPOSE: the legacy population is an independent minter of
# the pre-revision-2 world and must never be re-derived from the shared
# registry. These mint revision 2 and the binding-rule negatives.
rev2_claims = Map.put(genesis_claims, "protocol_revision", 2)

rev1_ed25519_descriptor =
  sign_compact.(
    genesis_claims,
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+party",
    :party_descriptor_content
  )

rev2_ed25519_descriptor =
  sign_compact.(
    rev2_claims,
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+party",
    :party_descriptor_content
  )

rev2_eddsa_descriptor =
  sign_compact.(
    rev2_claims,
    "genesis-key",
    genesis_private,
    "EdDSA",
    "cap+party",
    :party_descriptor_content
  )

rev3_descriptor =
  sign_compact.(
    Map.put(genesis_claims, "protocol_revision", 3),
    "genesis-key",
    genesis_private,
    "EdDSA",
    "cap+party",
    :party_descriptor_content
  )

rev4_descriptor =
  sign_compact.(
    Map.put(genesis_claims, "protocol_revision", 4),
    "genesis-key",
    genesis_private,
    "EdDSA",
    "cap+party",
    :party_descriptor_content
  )

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
    "id" => "descriptor-rev2-ed25519-valid",
    "surface" => "party_descriptor.verify",
    "class" => "valid",
    "input" => %{"compact" => rev2_ed25519_descriptor.compact, "predecessor" => nil},
    "expect" =>
      valid.(%{
        "descriptor_digest" => rev2_ed25519_descriptor.digest,
        "party_id" => rev2_ed25519_descriptor.digest,
        "descriptor_number" => 1
      })
  },
  %{
    "id" => "descriptor-rev2-eddsa-compat-valid",
    "surface" => "party_descriptor.verify",
    "class" => "valid",
    "input" => %{"compact" => rev2_eddsa_descriptor.compact, "predecessor" => nil},
    "expect" =>
      valid.(%{
        "descriptor_digest" => rev2_eddsa_descriptor.digest,
        "party_id" => rev2_eddsa_descriptor.digest,
        "descriptor_number" => 1
      })
  },
  %{
    "id" => "descriptor-rev1-ed25519-rejected",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => rev1_ed25519_descriptor.compact, "predecessor" => nil},
    "expect" => invalid.("protected_header_invalid")
  },
  %{
    "id" => "descriptor-rev3-eddsa-valid",
    "surface" => "party_descriptor.verify",
    "class" => "valid",
    "input" => %{"compact" => rev3_descriptor.compact, "predecessor" => nil},
    "expect" =>
      valid.(%{
        "descriptor_digest" => rev3_descriptor.digest,
        "party_id" => rev3_descriptor.digest,
        "descriptor_number" => 1
      })
  },
  %{
    "id" => "descriptor-rev4-fails-closed",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => rev4_descriptor.compact, "predecessor" => nil},
    "expect" => invalid.("protected_header_invalid")
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
        },
        "sibling_descriptors" => []
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
        "positions" => %{
          genesis.digest => "contested",
          left.digest => "contested",
          right.digest => "contested"
        },
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
  },
  %{
    "id" => "descriptor-effective-from-timestamp-floor",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => long_fraction_genesis.compact, "predecessor" => nil},
    "expect" => invalid.("constraint_violation")
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

# Decode strictness a second implementation can get wrong while still passing
# the cases above: the bytes must be canonical, members unique, and every
# member must meet its schema type and constraint.
revision_text = canonical.(revision_claims)

revision_text_case = fn id, class, text, expectation ->
  %{
    "id" => id,
    "surface" => "charter_revision.decode",
    "class" => class,
    "input" => %{"text" => text},
    "expect" => expectation
  }
end

[_issuer | single_party] = revision_claims["parties"]

revision_cases =
  revision_cases ++
    [
      revision_text_case.(
        "charter-revision-insignificant-whitespace",
        "non_canonical_bytes",
        String.replace(revision_text, ~s("parties":), ~s("parties": ), global: false),
        invalid.("non_canonical_bytes")
      ),
      revision_text_case.(
        "charter-revision-duplicate-member",
        "invalid_encoding",
        String.replace(revision_text, ~s({"abp_bindings"), ~s({"abp_bindings":[],"abp_bindings"),
          global: false
        ),
        invalid.("duplicate_member")
      ),
      revision_case.(
        "charter-revision-precedence-outside-enumeration",
        "invalid_constraint",
        Map.put(revision_claims, "precedence_declaration", "unlisted_precedence"),
        invalid.("constraint_violation")
      ),
      revision_case.(
        "charter-revision-effective-from-unparsable",
        "invalid_constraint",
        Map.put(revision_claims, "effective_from", "not-a-time"),
        invalid.("timestamp_invalid")
      ),
      revision_case.(
        "charter-revision-unknown-protocol-revision",
        "invalid_constraint",
        Map.put(revision_claims, "protocol_revision", 99),
        invalid.("constraint_violation")
      ),
      revision_case.(
        "charter-revision-number-as-string",
        "invalid_type",
        Map.put(revision_claims, "revision_number", "1"),
        invalid.("invalid_type")
      ),
      revision_case.(
        "charter-revision-legal-text-as-number",
        "invalid_type",
        Map.put(revision_claims, "legal_text", 5),
        invalid.("invalid_type")
      ),
      revision_case.(
        "charter-revision-one-party",
        "invalid_cardinality",
        Map.put(revision_claims, "parties", single_party),
        invalid.("cardinality_violation")
      ),
      revision_case.(
        "charter-revision-three-parties",
        "invalid_cardinality",
        Map.put(
          revision_claims,
          "parties",
          revision_claims["parties"] ++
            [
              %{
                "party_descriptor_digest" =>
                  :party_descriptor_content |> Digest.hash("party:third") |> Digest.to_tagged(),
                "role" => "observer"
              }
            ]
        ),
        invalid.("cardinality_violation")
      )
    ]

acceptance_compact = fn claims, kid, private ->
  sign_compact.(claims, kid, private, "EdDSA", "cap+acceptance", :acceptance_content)
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

# The revision-2 acceptance anchoring the revision-1 genesis — the
# charters-outlive-revisions flow: after cutover, every acceptance of a
# pre-existing charter is exactly this shape.
rev2_acceptance =
  sign_compact.(
    Map.put(acceptance_claims_value, "protocol_revision", 2),
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+acceptance",
    :acceptance_content
  )

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
    "id" => "acceptance-rev2-anchors-rev1-charter",
    "surface" => "acceptance.verify",
    "class" => "valid",
    "input" => %{
      "compact" => rev2_acceptance.compact,
      "revision_text" => revision_bytes,
      "descriptor_compacts" => [genesis.compact]
    },
    "expect" =>
      valid.(%{
        "acceptance_digest" => rev2_acceptance.digest,
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
    "id" => "termination-wrong-revision-claims",
    "surface" => "termination.verify",
    "class" => "invalid_constraint",
    "input" =>
      termination_input.(
        termination_compact.(
          Map.put(termination_claims, "governing_revision_digest", genesis.digest),
          "genesis-key",
          genesis_private
        ).compact
      ),
    "expect" => invalid.("termination_claims_mismatch")
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

{acceptor_key, acceptor_private} = descriptor_key.(7, "acceptor-key")

acceptor =
  descriptor_compact.(
    %{
      "protocol_revision" => 1,
      "descriptor_number" => 1,
      "verification_keys" => [acceptor_key],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:00Z"
    },
    "acceptor-key",
    acceptor_private
  )

chain_genesis_claims =
  put_in(revision_claims, ["parties"], [
    %{"party_descriptor_digest" => genesis.digest, "role" => "issuer"},
    %{"party_descriptor_digest" => acceptor.digest, "role" => "acceptor"}
  ])

chain_genesis_bytes = canonical.(chain_genesis_claims)

chain_genesis_digest =
  :charter_revision_content |> Digest.hash(chain_genesis_bytes) |> Digest.to_tagged()

chain_successor = fn previous_digest, number, legal, supersedes ->
  claims =
    chain_genesis_claims
    |> Map.merge(%{
      "charter_id" => chain_genesis_digest,
      "revision_number" => number,
      "prev_revision_digest" => previous_digest,
      "effective_from" =>
        ~U[2026-08-25 12:00:00Z]
        |> DateTime.add(number - 1)
        |> DateTime.to_iso8601(),
      "legal_text" => %{
        "content_digest" => :legal_text |> Digest.hash(legal) |> Digest.to_tagged(),
        "media_type" => "text/plain"
      }
    })

  claims = if supersedes == [], do: claims, else: Map.put(claims, "supersedes", supersedes)
  bytes = canonical.(claims)
  digest = :charter_revision_content |> Digest.hash(bytes) |> Digest.to_tagged()
  %{claims: claims, bytes: bytes, digest: digest}
end

chain_left = chain_successor.(chain_genesis_digest, 2, "left terms\n", [])
chain_right = chain_successor.(chain_genesis_digest, 2, "right terms\n", [])

chain_repair =
  chain_successor.(
    chain_left.digest,
    3,
    "reconciled terms\n",
    Enum.sort([chain_left.digest, chain_right.digest])
  )

chain_acceptance = fn revision_claims_value,
                      revision_digest_value,
                      descriptor_digest,
                      role,
                      kid,
                      private ->
  claims = %{
    "protocol_revision" => 1,
    "charter_id" => chain_genesis_digest,
    "revision_number" => revision_claims_value["revision_number"],
    "revision_digest" => revision_digest_value,
    "party_descriptor_digest" => descriptor_digest,
    "party_role" => role,
    "accepted_at" => "2026-08-25T13:00:00Z"
  }

  claims =
    if revision_claims_value["revision_number"] == 1,
      do: claims,
      else: Map.put(claims, "prev_revision_digest", revision_claims_value["prev_revision_digest"])

  acceptance_compact.(claims, kid, private).compact
end

dual_chain_acceptances = fn revision_claims_value, revision_digest_value ->
  [
    chain_acceptance.(
      revision_claims_value,
      revision_digest_value,
      genesis.digest,
      "issuer",
      "genesis-key",
      genesis_private
    ),
    chain_acceptance.(
      revision_claims_value,
      revision_digest_value,
      acceptor.digest,
      "acceptor",
      "acceptor-key",
      acceptor_private
    )
  ]
end

chain_revision = %{
  claims: chain_genesis_claims,
  bytes: chain_genesis_bytes,
  digest: chain_genesis_digest
}

chain_input = fn revisions ->
  %{
    "revisions" => Enum.map(revisions, & &1.bytes),
    "acceptances" => Enum.flat_map(revisions, &dual_chain_acceptances.(&1.claims, &1.digest)),
    "descriptors" => [genesis.compact, acceptor.compact],
    "terminations" => []
  }
end

valid_chain_input = chain_input.([chain_revision])
forked_chain_input = chain_input.([chain_revision, chain_left, chain_right])
repaired_chain_input = chain_input.([chain_revision, chain_left, chain_right, chain_repair])
precedence_input = chain_input.([chain_revision, chain_left])

profile_cases = [
  %{
    "id" => "chain-profile-narrow-valid",
    "surface" => "chain.verify_profile",
    "class" => "profile_narrow_valid",
    "input" =>
      Map.put(valid_chain_input, "profile", %{
        "algorithms" => ["EdDSA"],
        "revisions" => %{"min" => 1, "max" => 1}
      }),
    "expect" => valid.(%{"charter_id" => chain_genesis_digest, "topology" => "linear"})
  },
  %{
    "id" => "chain-profile-algorithm-outside",
    "surface" => "chain.verify_profile",
    "class" => "profile_algorithm_outside",
    "input" =>
      Map.put(valid_chain_input, "profile", %{
        "algorithms" => ["Ed25519"],
        "revisions" => %{"min" => 1, "max" => 3}
      }),
    "expect" => invalid.("algorithm_outside_profile")
  },
  %{
    "id" => "chain-profile-revision-outside",
    "surface" => "chain.verify_profile",
    "class" => "profile_revision_outside",
    "input" =>
      Map.put(valid_chain_input, "profile", %{
        "algorithms" => ["EdDSA", "Ed25519"],
        "revisions" => %{"min" => 2, "max" => 3}
      }),
    "expect" => invalid.("revision_outside_profile")
  }
]

chain_cases = [
  %{
    "id" => "chain-dual-acceptance-valid",
    "surface" => "chain.verify",
    "class" => "valid",
    "input" => valid_chain_input,
    "expect" =>
      valid.(%{
        "charter_id" => chain_genesis_digest,
        "topology" => "linear",
        "accepted_revision_digests" => [chain_genesis_digest],
        "superseded_revision_digests" => []
      })
  },
  %{
    "id" => "chain-accepted-sibling-fork",
    "surface" => "chain.verify",
    "class" => "chain_fork",
    "input" => forked_chain_input,
    "expect" =>
      valid.(%{
        "charter_id" => chain_genesis_digest,
        "topology" => "forked",
        "accepted_revision_digests" =>
          Enum.sort([chain_genesis_digest, chain_left.digest, chain_right.digest]),
        "superseded_revision_digests" => []
      })
  },
  %{
    "id" => "chain-bilateral-supersession-repair",
    "surface" => "chain.verify",
    "class" => "supersession",
    "input" => repaired_chain_input,
    "expect" =>
      valid.(%{
        "charter_id" => chain_genesis_digest,
        "topology" => "linear",
        "accepted_revision_digests" =>
          Enum.sort([
            chain_genesis_digest,
            chain_left.digest,
            chain_right.digest,
            chain_repair.digest
          ]),
        "superseded_revision_digests" => Enum.sort([chain_left.digest, chain_right.digest])
      })
  },
  %{
    "id" => "governing-revision-start-inclusive-precedence",
    "surface" => "governing_revision",
    "class" => "precedence_selection",
    "input" =>
      Map.put(precedence_input, "queries", [
        %{"at" => "2026-08-25T11:59:59Z", "governing_revision" => "none"},
        %{"at" => "2026-08-25T12:00:00Z", "governing_revision" => chain_genesis_digest},
        %{"at" => "2026-08-25T12:00:01Z", "governing_revision" => chain_left.digest}
      ]),
    "expect" =>
      valid.(%{
        "governing_revisions" => ["none", chain_genesis_digest, chain_left.digest]
      })
  }
]

supplemental_case_ids =
  MapSet.new(~w(
    revision-indexed-price-valid
    revision-indexed-price-formula-invalid
    revision-extension-unknown-critical
    receipt-signed-governing-match
    receipt-outcome-indeterminate
    receipt-rejected-effect-invalid
    receipt-signature-invalid
    receipt-hidden-sibling-conflict
    receipt-indexed-price-observation-quarantine
    descriptor-mldsa65-rev3-valid
    descriptor-mldsa65-rev2-rejected
    descriptor-mldsa-key-in-rev2-rejected
    descriptor-mldsa65-key-length-rejected
    descriptor-mldsa65-signature-length-rejected
    chain-pq-key-bridge
    chain-mldsa-mixed-revision
    acceptance-mldsa65-rev3-valid
    receipt-mldsa65-rev3-valid
  ))

supplemental_cases =
  root
  |> Path.join("cases/*.json")
  |> Path.wildcard()
  |> Enum.flat_map(fn path -> path |> File.read!() |> :json.decode() |> Map.fetch!("cases") end)
  |> Enum.filter(&MapSet.member?(supplemental_case_ids, &1["id"]))

unless MapSet.new(supplemental_cases, & &1["id"]) == supplemental_case_ids do
  raise "supplemental conformance case set is incomplete"
end

coverage_descriptor_compact = fn claims, kid, private, extra_header ->
  protected =
    canonical.(Map.merge(%{"alg" => "EdDSA", "kid" => kid, "typ" => "cap+party"}, extra_header))

  payload = canonical.(claims)
  message = Base64Url.encode(protected) <> "." <> Base64Url.encode(payload)
  signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])
  message <> "." <> Base64Url.encode(signature)
end

header_extra_descriptor =
  coverage_descriptor_compact.(genesis_claims, "genesis-key", genesis_private, %{"jwk" => 1})

genesis_with_predecessor =
  coverage_descriptor_compact.(
    Map.put(
      genesis_claims,
      "prev_descriptor_digest",
      "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    ),
    "genesis-key",
    genesis_private,
    %{}
  )

unresolved_kid_descriptor =
  coverage_descriptor_compact.(genesis_claims, "nonexistent-key", genesis_private, %{})

unparsable_effective_from =
  coverage_descriptor_compact.(
    Map.put(genesis_claims, "effective_from", "garbage"),
    "genesis-key",
    genesis_private,
    %{}
  )

acceptance_without_prev_at_two =
  acceptance_claims_value
  |> Map.put("revision_number", 2)
  |> Map.delete("prev_revision_digest")
  |> acceptance_compact.("genesis-key", genesis_private)

price_terms_body = %{
  "base_amount_minor" => 10000,
  "cap_amount_minor" => 12000,
  "currency" => "USD",
  "floor_amount_minor" => 9000,
  "formula" => "index_plus_spread",
  "index" => %{
    "observation_lag_days" => 2,
    "series_document_digest" => "sha-256:DAb9EB60I7UfAUC37DnTnkuaQd0GC3aUJCd7dMQG0Ck",
    "series_id" => "EXAMPLE-CPI"
  },
  "spread_bps" => 125,
  "tolerance_bps" => 50
}

extension_case = fn id, code, critical, optional ->
  %{
    "id" => id,
    "surface" => "charter_revision.decode",
    "class" => "extension_invalid",
    "input" => %{
      "text" =>
        canonical.(
          Map.put(revision_claims, "extensions", %{"critical" => critical, "optional" => optional})
        )
    },
    "expect" => invalid.(code)
  }
end

receipt_compact = fn claims, kid, private ->
  protected = canonical.(%{"alg" => "EdDSA", "kid" => kid, "typ" => "cap+receipt"})
  payload = canonical.(claims)
  message = Base64Url.encode(protected) <> "." <> Base64Url.encode(payload)
  signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])
  message <> "." <> Base64Url.encode(signature)
end

receipt_claims = %{
  "protocol_revision" => 1,
  "charter_id" => chain_genesis_digest,
  "revision_number" => 1,
  "revision_digest" => chain_genesis_digest,
  "issuing_party_role" => "issuer",
  "agent_party_role" => "issuer",
  "deployment_digest" => "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo",
  "grant" => %{
    "scheme" => "bap",
    "id" => "grant-2026-07-27-001",
    "grant_digest" => "sha-256:5k224cZ_lMI9VoUZ_fYM31ZJAcnJiht0GYEpnhes_ZI"
  },
  "invocation_id" => "123e4567-e89b-42d3-a456-426614174000",
  "decision" => "accepted",
  "outcome" => "effect_committed",
  "occurred_at" => "2026-08-25T12:00:01Z",
  "recorded_at" => "2026-08-25T12:00:02Z",
  "extensions" => %{"critical" => %{}, "optional" => %{}}
}

receipt_chain_input = chain_input.([chain_revision])

mismatched_receipt =
  receipt_claims
  |> Map.put("revision_digest", "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
  |> Map.put("charter_id", "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
  |> receipt_compact.("genesis-key", genesis_private)

bap_without_grant_digest =
  receipt_claims
  |> Map.put("grant", %{"scheme" => "bap", "id" => "grant-2026-07-27-001"})
  |> receipt_compact.("genesis-key", genesis_private)

schema_unavailable_receipt =
  receipt_claims
  |> Map.put("extensions", %{
    "critical" => %{},
    "optional" => %{"com.example.charter/default" => %{}}
  })
  |> receipt_compact.("genesis-key", genesis_private)

coverage_cases = [
  %{
    "id" => "base64url-invalid-character",
    "surface" => "base64url.decode",
    "class" => "invalid_encoding",
    "input" => %{"text" => "A!"},
    "expect" => invalid.("base64url_invalid")
  },
  %{
    "id" => "json-trailing-bytes",
    "surface" => "json.decode",
    "class" => "invalid_encoding",
    "input" => %{"text" => "{\"a\":1} x"},
    "expect" => invalid.("trailing_bytes")
  },
  %{
    "id" => "json-invalid-syntax",
    "surface" => "json.decode",
    "class" => "invalid_encoding",
    "input" => %{"text" => "{"},
    "expect" => invalid.("invalid_syntax")
  },
  %{
    "id" => "json-duplicate-member",
    "surface" => "json.decode",
    "class" => "invalid_encoding",
    "input" => %{"text" => "{\"a\":1,\"a\":2}"},
    "expect" => invalid.("duplicate_member")
  },
  %{
    "id" => "json-duplicate-member-not-last",
    "surface" => "json.decode",
    "class" => "invalid_encoding",
    "input" => %{"text" => "{\"a\":1,\"a\":2,\"b\":3}"},
    "expect" => invalid.("duplicate_member")
  },
  %{
    "id" => "json-integer-like-member-order",
    "surface" => "json.decode",
    "class" => "valid",
    "input" => %{"text" => "{\"10\":1,\"9\":2}"},
    "expect" =>
      valid.(%{
        "tag" => "object",
        "members" => [
          ["10", %{"tag" => "integer", "value" => 1}],
          ["9", %{"tag" => "integer", "value" => 2}]
        ]
      })
  },
  %{
    "id" => "json-number-not-double-expressible",
    "surface" => "json.decode",
    "class" => "invalid_type",
    "input" => %{"text" => "{\"n\":9007199254740993}"},
    "expect" => invalid.("number_not_double_expressible")
  },
  %{
    "id" => "json-number-overflow",
    "surface" => "json.decode",
    "class" => "invalid_type",
    "input" => %{"text" => "{\"n\":1e999}"},
    "expect" => invalid.("invalid_number")
  },
  %{
    "id" => "json-limits-invalid",
    "surface" => "json.decode",
    "class" => "invalid_type",
    "input" => %{"text" => "{}", "limits" => %{"max_bytes" => -1}},
    "expect" => invalid.("invalid_limits")
  },
  %{
    "id" => "canonical-duplicate-member",
    "surface" => "canonicalization.encode",
    "class" => "invalid_encoding",
    "input" => %{
      "tag" => "object",
      "members" => [
        ["a", %{"tag" => "integer", "value" => 1}],
        ["a", %{"tag" => "integer", "value" => 2}]
      ]
    },
    "expect" => invalid.("duplicate_member")
  },
  %{
    "id" => "canonical-integer-magnitude",
    "surface" => "canonicalization.encode",
    "class" => "invalid_type",
    "input" => %{"tag" => "integer", "text_value" => "9007199254740993"},
    "expect" => invalid.("integer_magnitude")
  },
  %{
    "id" => "digest-unsupported-algorithm",
    "surface" => "digest.hash",
    "class" => "invalid_type",
    "input" => %{
      "domain" => "legal_text",
      "bytes_base64url" => "eA",
      "tagged" => "sha-512:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    "expect" => invalid.("digest_algorithm_unsupported")
  },
  %{
    "id" => "digest-invalid-encoding",
    "surface" => "digest.hash",
    "class" => "invalid_type",
    "input" => %{"domain" => "legal_text", "bytes_base64url" => "eA", "tagged" => "sha-256:@@@"},
    "expect" => invalid.("digest_encoding_invalid")
  },
  %{
    "id" => "descriptor-compact-malformed",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_encoding",
    "input" => %{"compact" => "abc", "predecessor" => nil},
    "expect" => invalid.("compact_invalid")
  },
  %{
    "id" => "descriptor-header-extra-member",
    "surface" => "party_descriptor.verify",
    "class" => "unknown_member",
    "input" => %{"compact" => header_extra_descriptor, "predecessor" => nil},
    "expect" => invalid.("protected_header_invalid")
  },
  %{
    "id" => "descriptor-genesis-with-predecessor",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => genesis_with_predecessor, "predecessor" => nil},
    "expect" => invalid.("descriptor_invalid")
  },
  %{
    "id" => "descriptor-key-id-unresolved",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => unresolved_kid_descriptor, "predecessor" => nil},
    "expect" => invalid.("descriptor_key_invalid")
  },
  %{
    "id" => "descriptor-timestamp-unparsable",
    "surface" => "party_descriptor.verify",
    "class" => "invalid_constraint",
    "input" => %{"compact" => unparsable_effective_from, "predecessor" => nil},
    "expect" => invalid.("timestamp_invalid")
  },
  %{
    "id" => "acceptance-invalid-coordinates",
    "surface" => "acceptance.verify",
    "class" => "invalid_constraint",
    "input" => %{
      "compact" => acceptance_without_prev_at_two.compact,
      "descriptor_compacts" => [genesis.compact],
      "revision_text" => revision_bytes
    },
    "expect" => invalid.("acceptance_invalid")
  },
  %{
    "id" => "acceptance-equivocation-not-pairable",
    "surface" => "acceptance.equivocation",
    "class" => "invalid_constraint",
    "input" => %{
      "descriptor_compacts" => [genesis.compact],
      "signed_revisions" => [
        %{"revision_text" => revision_bytes, "compact" => acceptance.compact},
        %{"revision_text" => left_revision_bytes, "compact" => left_acceptance.compact}
      ]
    },
    "expect" => invalid.("acceptance_equivocation_invalid")
  },
  extension_case.(
    "revision-extension-criticality-conflict",
    "extension_criticality_conflict",
    %{"com.example.charter/default" => %{}},
    %{}
  ),
  extension_case.(
    "revision-extension-duplicate",
    "extension_duplicate",
    %{"com.example/pricing-indexed" => price_terms_body},
    %{"com.example/pricing-indexed" => price_terms_body}
  ),
  extension_case.(
    "revision-extension-namespace-invalid",
    "extension_namespace_invalid",
    %{"Not-A-Ns/body" => %{}},
    %{}
  ),
  extension_case.(
    "revision-extension-retired-critical",
    "extension_retired",
    %{"com.example/retired-profile" => %{}},
    %{}
  ),
  extension_case.("revision-extension-scope-invalid", "extension_scope_invalid", %{}, %{
    "com.example/pricing-indexed-observation" => %{}
  }),
  %{
    "id" => "receipt-compact-malformed",
    "surface" => "receipt.verify",
    "class" => "invalid_encoding",
    "input" => %{"chain" => receipt_chain_input, "compact" => "abc"},
    "expect" => invalid.("compact_invalid")
  },
  %{
    "id" => "receipt-bap-grant-without-digest",
    "surface" => "receipt.verify",
    "class" => "invalid_encoding",
    "input" => %{"chain" => receipt_chain_input, "compact" => bap_without_grant_digest},
    "expect" => invalid.("receipt_invalid")
  },
  %{
    "id" => "receipt-claims-mismatch",
    "surface" => "receipt.verify",
    "class" => "invalid_constraint",
    "input" => %{"chain" => receipt_chain_input, "compact" => mismatched_receipt},
    "expect" => invalid.("receipt_claims_mismatch")
  },
  %{
    "id" => "receipt-extension-schema-unavailable",
    "surface" => "receipt.verify",
    "class" => "extension_invalid",
    "input" => %{"chain" => receipt_chain_input, "compact" => schema_unavailable_receipt},
    "expect" => invalid.("extension_schema_unavailable")
  },
  %{
    "id" => "chain-empty-revisions",
    "surface" => "chain.verify",
    "class" => "chain_invalid",
    "input" => %{
      "revisions" => [],
      "acceptances" => [],
      "descriptors" => [genesis.compact, acceptor.compact],
      "terminations" => []
    },
    "expect" => invalid.("chain_invalid")
  }
]

# Closed claim sets: one extra member in otherwise valid, validly signed claims
# rejects on every signed surface.
extra_member = fn claims -> Map.put(claims, "note", "unlisted member") end

closed_claims_cases = [
  %{
    "id" => "acceptance-claims-unknown-member",
    "surface" => "acceptance.verify",
    "class" => "unknown_member",
    "input" => %{
      "compact" =>
        acceptance_claims_value
        |> extra_member.()
        |> acceptance_compact.("genesis-key", genesis_private)
        |> Map.fetch!(:compact),
      "revision_text" => revision_bytes,
      "descriptor_compacts" => [genesis.compact]
    },
    "expect" => invalid.("unknown_member")
  },
  %{
    "id" => "termination-claims-unknown-member",
    "surface" => "termination.verify",
    "class" => "unknown_member",
    "input" =>
      termination_input.(
        termination_claims
        |> extra_member.()
        |> termination_compact.("genesis-key", genesis_private)
        |> Map.fetch!(:compact)
      ),
    "expect" => invalid.("unknown_member")
  },
  %{
    "id" => "receipt-claims-unknown-member",
    "surface" => "receipt.verify",
    "class" => "unknown_member",
    "input" => %{
      "chain" => receipt_chain_input,
      "compact" =>
        receipt_claims |> extra_member.() |> receipt_compact.("genesis-key", genesis_private)
    },
    "expect" => invalid.("unknown_member")
  },
  %{
    "id" => "descriptor-claims-unknown-member",
    "surface" => "party_descriptor.verify",
    "class" => "unknown_member",
    "input" => %{
      "compact" =>
        coverage_descriptor_compact.(
          extra_member.(genesis_claims),
          "genesis-key",
          genesis_private,
          %{}
        ),
      "predecessor" => nil
    },
    "expect" => invalid.("unknown_member")
  }
]

# A verified termination closes the charter at its effective instant:
# governing selection returns none from then on, and a receipt for an effect
# after that instant no longer matches a governing revision.
chain_termination =
  termination_claims
  |> Map.merge(%{
    "charter_id" => chain_genesis_digest,
    "governing_revision_digest" => chain_genesis_digest
  })
  |> termination_compact.("genesis-key", genesis_private)

terminated_chain_input = %{valid_chain_input | "terminations" => [chain_termination.compact]}

post_termination_receipt_claims =
  Map.merge(receipt_claims, %{
    "occurred_at" => "2026-08-26T13:00:01Z",
    "recorded_at" => "2026-08-26T13:00:02Z"
  })

termination_effect_cases = [
  %{
    "id" => "governing-revision-closed-by-termination",
    "surface" => "governing_revision",
    "class" => "terminated",
    "input" =>
      Map.put(terminated_chain_input, "queries", [
        %{"at" => "2026-08-26T12:59:59Z", "governing_revision" => chain_genesis_digest},
        %{"at" => "2026-08-26T13:00:00Z", "governing_revision" => "none"},
        %{"at" => "2026-08-26T13:00:01Z", "governing_revision" => "none"}
      ]),
    "expect" => valid.(%{"governing_revisions" => [chain_genesis_digest, "none", "none"]})
  },
  %{
    "id" => "receipt-after-termination-mismatch",
    "surface" => "receipt.verify",
    "class" => "terminated",
    "input" => %{
      "chain" => terminated_chain_input,
      "compact" =>
        receipt_compact.(post_termination_receipt_claims, "genesis-key", genesis_private)
    },
    "expect" =>
      valid.(%{
        "receipt_digest" =>
          :receipt_content
          |> Digest.hash(canonical.(post_termination_receipt_claims))
          |> Digest.to_tagged(),
        "revision_number" => 1,
        "revision_digest" => chain_genesis_digest,
        "decision" => "accepted",
        "outcome" => "effect_committed",
        "chain_conflict" => "none",
        "governing_match" => "mismatch",
        "deployment_digest_matched" => true,
        "optional_extensions_retained" => []
      })
  }
]

# Descriptor histories are grouped per party: one history per descriptor
# chain, a successor must name its party, and a chain view must carry exactly
# the histories of the revision's parties.
{successor_key, _successor_private} = descriptor_key.(5, "successor-key")

successor_without_party =
  descriptor_compact.(
    %{
      "protocol_revision" => 1,
      "descriptor_number" => 2,
      "prev_descriptor_digest" => genesis.digest,
      "verification_keys" => [successor_key],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:01Z"
    },
    "genesis-key",
    genesis_private
  )

party_grouping_cases = [
  %{
    "id" => "descriptor-chain-two-party-set",
    "surface" => "descriptor_chain.verify",
    "class" => "chain_invalid",
    "input" => %{"compacts" => [genesis.compact, acceptor.compact]},
    "expect" => invalid.("descriptor_chain_invalid")
  },
  %{
    "id" => "descriptor-chain-successor-without-party",
    "surface" => "descriptor_chain.verify",
    "class" => "chain_invalid",
    "input" => %{"compacts" => [genesis.compact, successor_without_party.compact]},
    "expect" => invalid.("descriptor_chain_invalid")
  },
  %{
    "id" => "chain-one-party-history",
    "surface" => "chain.verify",
    "class" => "chain_invalid",
    "input" => %{valid_chain_input | "descriptors" => [genesis.compact]},
    "expect" => invalid.("chain_invalid")
  }
]

# The artifact-set ceilings bound a chain view: max_artifact_set_items caps
# each list, max_artifact_set_bytes caps the total over all lists. Each holds
# at its exact bound and rejects one below it.
[dual_acceptance_valid] = Enum.filter(chain_cases, &(&1["id"] == "chain-dual-acceptance-valid"))

view_lists = Enum.map(~w(revisions acceptances descriptors terminations), &valid_chain_input[&1])
view_item_count = view_lists |> Enum.map(&length/1) |> Enum.max()
view_byte_count = view_lists |> List.flatten() |> Enum.map(&byte_size/1) |> Enum.sum()

set_limit_case = fn id, class, limits, expectation ->
  %{
    "id" => id,
    "surface" => "chain.verify",
    "class" => class,
    "input" => Map.put(valid_chain_input, "limits", limits),
    "expect" => expectation
  }
end

set_limit_cases = [
  set_limit_case.(
    "chain-artifact-set-items-exact-bound",
    "exact_bound",
    %{"max_artifact_set_items" => view_item_count},
    dual_acceptance_valid["expect"]
  ),
  set_limit_case.(
    "chain-artifact-set-items-maximum-plus-one",
    "maximum_plus_one",
    %{"max_artifact_set_items" => view_item_count - 1},
    invalid.("limit_exceeded")
  ),
  set_limit_case.(
    "chain-artifact-set-bytes-exact-bound",
    "exact_bound",
    %{"max_artifact_set_bytes" => view_byte_count},
    dual_acceptance_valid["expect"]
  ),
  set_limit_case.(
    "chain-artifact-set-bytes-maximum-plus-one",
    "maximum_plus_one",
    %{"max_artifact_set_bytes" => view_byte_count - 1},
    invalid.("limit_exceeded")
  )
]

# The indexed-price critical body is closed and fully typed; every member
# contract holds, not only the formula.
price_revision_case = fn id, body, code ->
  revision_case.(
    id,
    "extension_invalid",
    Map.put(revision_claims, "extensions", %{
      "critical" => %{"com.example/pricing-indexed" => body},
      "optional" => %{}
    }),
    invalid.(code)
  )
end

observation_receipt = fn body ->
  receipt_claims
  |> Map.put("extensions", %{
    "critical" => %{},
    "optional" => %{"com.example/pricing-indexed-observation" => body}
  })
  |> receipt_compact.("genesis-key", genesis_private)
end

price_body_cases = [
  price_revision_case.(
    "revision-indexed-price-missing-currency",
    Map.delete(price_terms_body, "currency"),
    "missing_required"
  ),
  price_revision_case.(
    "revision-indexed-price-unlisted-currency",
    Map.put(price_terms_body, "currency", "XXQ"),
    "constraint_violation"
  ),
  price_revision_case.(
    "revision-indexed-price-spread-out-of-range",
    Map.put(price_terms_body, "spread_bps", 10_001),
    "constraint_violation"
  ),
  price_revision_case.(
    "revision-indexed-price-cap-below-floor",
    Map.put(price_terms_body, "cap_amount_minor", 8000),
    "cross_field_invalid"
  ),
  price_revision_case.(
    "revision-indexed-price-index-unknown-member",
    put_in(price_terms_body, ["index", "note"], "unlisted member"),
    "nested_invalid"
  ),
  %{
    "id" => "receipt-indexed-price-observation-negative-amount",
    "surface" => "receipt.verify",
    "class" => "extension_invalid",
    "input" => %{
      "chain" => receipt_chain_input,
      "compact" =>
        observation_receipt.(%{
          "observed_index_digest" => "sha-256:DAb9EB60I7UfAUC37DnTnkuaQd0GC3aUJCd7dMQG0Ck",
          "observation_instant" => "2026-08-25T12:00:00Z",
          "computed_amount_minor" => -1
        })
    },
    "expect" => invalid.("constraint_violation")
  }
]

# A charter's parties are distinct parties. One descriptor may not hold two
# roles, and two descriptors of the same party may not either: before 0.5.0 a
# single party could satisfy "every party accepted" that way while an
# unrelated history stood in the view.
{_left_key, left_private} = descriptor_key.(2, "left-key")

same_party_claims =
  Map.put(revision_claims, "parties", [
    %{"party_descriptor_digest" => genesis.digest, "role" => "issuer"},
    %{"party_descriptor_digest" => left.digest, "role" => "acceptor"}
  ])

same_party_bytes = canonical.(same_party_claims)

same_party_digest =
  :charter_revision_content |> Digest.hash(same_party_bytes) |> Digest.to_tagged()

same_party_acceptance = fn descriptor_digest, role, kid, private ->
  %{
    "protocol_revision" => 1,
    "charter_id" => same_party_digest,
    "revision_number" => 1,
    "revision_digest" => same_party_digest,
    "party_descriptor_digest" => descriptor_digest,
    "party_role" => role,
    "accepted_at" => "2026-08-25T13:00:00Z"
  }
  |> acceptance_compact.(kid, private)
  |> Map.fetch!(:compact)
end

distinct_party_cases = [
  revision_case.(
    "charter-revision-shared-descriptor",
    "invalid_constraint",
    put_in(revision_claims, ["parties", Access.at(1), "party_descriptor_digest"], genesis.digest),
    invalid.("revision_invalid")
  ),
  %{
    "id" => "chain-one-party-both-roles",
    "surface" => "chain.verify",
    "class" => "chain_invalid",
    "input" => %{
      "revisions" => [same_party_bytes],
      "acceptances" => [
        same_party_acceptance.(genesis.digest, "issuer", "genesis-key", genesis_private),
        same_party_acceptance.(left.digest, "acceptor", "left-key", left_private)
      ],
      "descriptors" => [genesis.compact, left.compact, acceptor.compact],
      "terminations" => []
    },
    "expect" => invalid.("chain_invalid")
  }
]

# RFC 3339 admits year 0000; both implementations must read it the same way.
year_zero_claims = Map.put(revision_claims, "effective_from", "0000-01-01T00:00:00Z")
year_zero_bytes = canonical.(year_zero_claims)

year_zero_cases = [
  revision_case.(
    "charter-revision-effective-from-year-zero",
    "valid",
    year_zero_claims,
    valid.(%{
      "revision_digest" =>
        :charter_revision_content |> Digest.hash(year_zero_bytes) |> Digest.to_tagged(),
      "revision_number" => 1,
      "precedence_declaration" => "legal_text_governs",
      "abp_binding" => %{
        "blueprint_id" => "example.demo/echo",
        "release_number" => 1,
        "content_digest" => "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
        "deployment_digest" => "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"
      }
    })
  )
]

# A digest inside signed claims is strict base64url: one changed spare bit
# makes a different spelling of the same bytes, and it must reject.
noncanonical_digest =
  String.slice(chain_genesis_digest, 0..-2//1) <>
    if(String.ends_with?(chain_genesis_digest, "o"), do: "p", else: "o")

strict_digest_cases = [
  %{
    "id" => "receipt-revision-digest-noncanonical",
    "surface" => "receipt.verify",
    "class" => "invalid_encoding",
    "input" => %{
      "chain" => receipt_chain_input,
      "compact" =>
        receipt_claims
        |> Map.put("revision_digest", noncanonical_digest)
        |> receipt_compact.("genesis-key", genesis_private)
    },
    "expect" => invalid.("receipt_invalid")
  }
]

# A two-party view holds exactly two key histories. Without that bound, a
# successor naming a third party, accepted by that party and the one who
# stays, would govern without the displaced party ever signing.
{third_key, third_private} = descriptor_key.(8, "third-key")

third =
  descriptor_compact.(
    %{
      "protocol_revision" => 1,
      "descriptor_number" => 1,
      "verification_keys" => [third_key],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:00Z"
    },
    "third-key",
    third_private
  )

displacing = chain_successor.(chain_genesis_digest, 2, "displacing terms\n", [])

displacing_claims =
  Map.put(displacing.claims, "parties", [
    %{"party_descriptor_digest" => genesis.digest, "role" => "issuer"},
    %{"party_descriptor_digest" => third.digest, "role" => "acceptor"}
  ])

displacing_bytes = canonical.(displacing_claims)

displacing_digest =
  :charter_revision_content |> Digest.hash(displacing_bytes) |> Digest.to_tagged()

displacement_cases = [
  %{
    "id" => "chain-two-party-third-history-displacement",
    "surface" => "chain.verify",
    "class" => "chain_invalid",
    "input" => %{
      "revisions" => [chain_genesis_bytes, displacing_bytes],
      "acceptances" =>
        dual_chain_acceptances.(chain_genesis_claims, chain_genesis_digest) ++
          [
            chain_acceptance.(
              displacing_claims,
              displacing_digest,
              genesis.digest,
              "issuer",
              "genesis-key",
              genesis_private
            ),
            chain_acceptance.(
              displacing_claims,
              displacing_digest,
              third.digest,
              "acceptor",
              "third-key",
              third_private
            )
          ],
      "descriptors" => [genesis.compact, acceptor.compact, third.compact],
      "terminations" => []
    },
    "expect" => invalid.("chain_invalid")
  }
]

# A caller's profile reaches the context a single-artifact call re-verifies:
# the supplied revision first, then the supplied descriptor history, then the
# artifact itself. Every artifact here is in profile except the context.
narrow_profile = %{"algorithms" => ["EdDSA", "Ed25519"], "revisions" => %{"min" => 1, "max" => 2}}
algorithm_profile = %{"algorithms" => ["Ed25519"], "revisions" => %{"min" => 1, "max" => 3}}

revision_profile = %{
  "algorithms" => ["EdDSA", "Ed25519"],
  "revisions" => %{"min" => 2, "max" => 3}
}

rev2_termination =
  sign_compact.(
    Map.put(termination_claims, "protocol_revision", 2),
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+termination",
    :termination_content
  )

rev2_receipt_claims = Map.put(receipt_claims, "protocol_revision", 2)

rev2_receipt =
  sign_compact.(
    rev2_receipt_claims,
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+receipt",
    :receipt_content
  )

rev1_receipt = receipt_compact.(receipt_claims, "genesis-key", genesis_private)

single_artifact_profile_cases = fn surface, prefix, compact, output ->
  input = %{
    "compact" => compact,
    "revision_text" => revision_bytes,
    "descriptor_compacts" => [genesis.compact]
  }

  [
    %{
      "id" => prefix <> "-profile-narrow-valid",
      "surface" => surface,
      "class" => "profile_narrow_valid",
      "input" => Map.put(input, "profile", narrow_profile),
      "expect" => valid.(output)
    },
    %{
      "id" => prefix <> "-profile-context-algorithm-outside",
      "surface" => surface,
      "class" => "profile_algorithm_outside",
      "input" => Map.put(input, "profile", algorithm_profile),
      "expect" => invalid.("algorithm_outside_profile")
    },
    %{
      "id" => prefix <> "-profile-context-revision-outside",
      "surface" => surface,
      "class" => "profile_revision_outside",
      "input" => Map.put(input, "profile", revision_profile),
      "expect" => invalid.("revision_outside_profile")
    }
  ]
end

# Only the supplied revision is outside the profile here: a revision-2
# charter beside a revision-1 descriptor and revision-1 artifacts, under a
# profile admitting revision 1 alone.
rev2_revision_claims = Map.put(revision_claims, "protocol_revision", 2)
rev2_revision_bytes = canonical.(rev2_revision_claims)

rev2_revision_digest =
  :charter_revision_content |> Digest.hash(rev2_revision_bytes) |> Digest.to_tagged()

revision_one_profile = %{
  "algorithms" => ["EdDSA", "Ed25519"],
  "revisions" => %{"min" => 1, "max" => 1}
}

rev2_revision_acceptance =
  rev2_revision_claims
  |> acceptance_claims.(rev2_revision_digest)
  |> acceptance_compact.("genesis-key", genesis_private)

rev2_revision_termination =
  termination_claims
  |> Map.merge(%{
    "charter_id" => rev2_revision_digest,
    "governing_revision_digest" => rev2_revision_digest
  })
  |> termination_compact.("genesis-key", genesis_private)

revision_only_outside = fn surface, prefix, compact ->
  %{
    "id" => prefix <> "-profile-revision-alone-outside",
    "surface" => surface,
    "class" => "profile_revision_outside",
    "input" => %{
      "compact" => compact,
      "revision_text" => rev2_revision_bytes,
      "descriptor_compacts" => [genesis.compact],
      "profile" => revision_one_profile
    },
    "expect" => invalid.("revision_outside_profile")
  }
end

# Both context axes are excluded: the supplied revision is revision 1 and
# the descriptor is EdDSA at revision 1, under an Ed25519-only profile for
# revisions 2 and 3. The revision is checked first, so the code is the
# revision's.
both_axes_profile = %{"algorithms" => ["Ed25519"], "revisions" => %{"min" => 2, "max" => 3}}

both_axes_outside = fn surface, prefix, compact ->
  %{
    "id" => prefix <> "-profile-revision-before-descriptor",
    "surface" => surface,
    "class" => "profile_revision_outside",
    "input" => %{
      "compact" => compact,
      "revision_text" => revision_bytes,
      "descriptor_compacts" => [genesis.compact],
      "profile" => both_axes_profile
    },
    "expect" => invalid.("revision_outside_profile")
  }
end

# Only the descriptor is outside, and only on the revision axis: a revision-2
# charter and a revision-2 Ed25519 artifact beside the revision-1 descriptor.
rev2_context_acceptance =
  sign_compact.(
    rev2_revision_claims
    |> acceptance_claims.(rev2_revision_digest)
    |> Map.put("protocol_revision", 2),
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+acceptance",
    :acceptance_content
  )

rev2_context_termination =
  sign_compact.(
    termination_claims
    |> Map.merge(%{
      "protocol_revision" => 2,
      "charter_id" => rev2_revision_digest,
      "governing_revision_digest" => rev2_revision_digest
    }),
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+termination",
    :termination_content
  )

descriptor_revision_outside = fn surface, prefix, compact ->
  %{
    "id" => prefix <> "-profile-descriptor-revision-outside",
    "surface" => surface,
    "class" => "profile_revision_outside",
    "input" => %{
      "compact" => compact,
      "revision_text" => rev2_revision_bytes,
      "descriptor_compacts" => [genesis.compact],
      "profile" => revision_profile
    },
    "expect" => invalid.("revision_outside_profile")
  }
end

# A successor descriptor verified against its supplied predecessor history:
# the profile reaches the predecessor too.
rev2_successor_key = descriptor_key.(6, "successor-key") |> elem(0)

rev2_successor =
  sign_compact.(
    %{
      "protocol_revision" => 2,
      "party_id" => genesis.digest,
      "descriptor_number" => 2,
      "prev_descriptor_digest" => genesis.digest,
      "verification_keys" => [rev2_successor_key],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:01Z"
    },
    "genesis-key",
    genesis_private,
    "Ed25519",
    "cap+party",
    :party_descriptor_content
  )

predecessor_case = fn id, class, profile, expectation ->
  %{
    "id" => id,
    "surface" => "party_descriptor.verify",
    "class" => class,
    "input" => %{
      "compact" => rev2_successor.compact,
      "predecessor_compacts" => [genesis.compact],
      "profile" => profile
    },
    "expect" => expectation
  }
end

# A receipt outside the profile whose kid names no key in the chain view: the
# profile rejection is reported, never a forgery verdict. The revision-1 chain
# is inside the profile; only the revision-2 receipt is outside it.
unknown_kid_receipt =
  sign_compact.(
    Map.put(receipt_claims, "protocol_revision", 2),
    "unknown-key",
    genesis_private,
    "Ed25519",
    "cap+receipt",
    :receipt_content
  ).compact

# Artifacts outside the profile whose kid names no key: the profile code is
# reported, not the key lookup failure. Their context is inside the profile.
unknown_kid_acceptance =
  sign_compact.(
    Map.put(acceptance_claims_value, "protocol_revision", 2),
    "unknown-key",
    genesis_private,
    "Ed25519",
    "cap+acceptance",
    :acceptance_content
  )

unknown_kid_termination =
  sign_compact.(
    Map.put(termination_claims, "protocol_revision", 2),
    "unknown-key",
    genesis_private,
    "Ed25519",
    "cap+termination",
    :termination_content
  )

unknown_kid_descriptor =
  sign_compact.(
    Map.put(genesis_claims, "protocol_revision", 2),
    "unknown-key",
    genesis_private,
    "Ed25519",
    "cap+party",
    :party_descriptor_content
  )

unknown_kid_case = fn surface, prefix, compact ->
  %{
    "id" => prefix <> "-profile-unknown-kid-revision-outside",
    "surface" => surface,
    "class" => "profile_revision_outside",
    "input" => %{
      "compact" => compact,
      "revision_text" => revision_bytes,
      "descriptor_compacts" => [genesis.compact],
      "profile" => revision_one_profile
    },
    "expect" => invalid.("revision_outside_profile")
  }
end

# A profile that names one axis leaves the other at its full range.
single_axis_case = %{
  "id" => "acceptance-profile-algorithms-only-valid",
  "surface" => "acceptance.verify",
  "class" => "profile_narrow_valid",
  "input" => %{
    "compact" => rev2_acceptance.compact,
    "revision_text" => revision_bytes,
    "descriptor_compacts" => [genesis.compact],
    "profile" => %{"algorithms" => ["EdDSA", "Ed25519"]}
  },
  "expect" =>
    valid.(%{
      "acceptance_digest" => rev2_acceptance.digest,
      "revision_digest" => revision_digest,
      "party_descriptor_digest" => genesis.digest,
      "descriptor_position" => "head"
    })
}

context_profile_cases =
  [
    single_axis_case,
    unknown_kid_case.("acceptance.verify", "acceptance", unknown_kid_acceptance.compact),
    unknown_kid_case.("termination.verify", "termination", unknown_kid_termination.compact),
    %{
      "id" => "descriptor-profile-unknown-kid-revision-outside",
      "surface" => "party_descriptor.verify",
      "class" => "profile_revision_outside",
      "input" => %{
        "compact" => unknown_kid_descriptor.compact,
        "predecessor" => nil,
        "profile" => revision_one_profile
      },
      "expect" => invalid.("revision_outside_profile")
    },
    predecessor_case.(
      "descriptor-profile-predecessor-narrow-valid",
      "profile_narrow_valid",
      narrow_profile,
      valid.(%{
        "descriptor_digest" => rev2_successor.digest,
        "party_id" => genesis.digest,
        "descriptor_number" => 2
      })
    ),
    predecessor_case.(
      "descriptor-profile-predecessor-algorithm-outside",
      "profile_algorithm_outside",
      algorithm_profile,
      invalid.("algorithm_outside_profile")
    ),
    predecessor_case.(
      "descriptor-profile-predecessor-revision-outside",
      "profile_revision_outside",
      revision_profile,
      invalid.("revision_outside_profile")
    ),
    both_axes_outside.("acceptance.verify", "acceptance", rev2_acceptance.compact),
    both_axes_outside.("termination.verify", "termination", rev2_termination.compact),
    descriptor_revision_outside.(
      "acceptance.verify",
      "acceptance",
      rev2_context_acceptance.compact
    ),
    descriptor_revision_outside.(
      "termination.verify",
      "termination",
      rev2_context_termination.compact
    ),
    %{
      "id" => "receipt-profile-unknown-kid-revision-outside",
      "surface" => "receipt.verify",
      "class" => "profile_revision_outside",
      "input" => %{
        "chain" => receipt_chain_input,
        "compact" => unknown_kid_receipt,
        "profile" => revision_one_profile
      },
      "expect" => invalid.("revision_outside_profile")
    },
    revision_only_outside.("acceptance.verify", "acceptance", rev2_revision_acceptance.compact),
    revision_only_outside.(
      "termination.verify",
      "termination",
      rev2_revision_termination.compact
    )
  ] ++
    single_artifact_profile_cases.(
      "acceptance.verify",
      "acceptance",
      rev2_acceptance.compact,
      %{
        "acceptance_digest" => rev2_acceptance.digest,
        "revision_digest" => revision_digest,
        "party_descriptor_digest" => genesis.digest,
        "descriptor_position" => "head"
      }
    ) ++
    single_artifact_profile_cases.(
      "termination.verify",
      "termination",
      rev2_termination.compact,
      %{
        "termination_digest" => rev2_termination.digest,
        "governing_revision_digest" => revision_digest,
        "party_descriptor_digest" => genesis.digest,
        "reason_code" => "mutual",
        "descriptor_position" => "head"
      }
    ) ++
    [
      %{
        "id" => "receipt-profile-narrow-valid",
        "surface" => "receipt.verify",
        "class" => "profile_narrow_valid",
        "input" => %{
          "chain" => receipt_chain_input,
          "compact" => rev2_receipt.compact,
          "profile" => narrow_profile
        },
        "expect" =>
          valid.(%{
            "receipt_digest" => rev2_receipt.digest,
            "revision_number" => 1,
            "revision_digest" => chain_genesis_digest,
            "decision" => "accepted",
            "outcome" => "effect_committed",
            "chain_conflict" => "none",
            "governing_match" => "match",
            "deployment_digest_matched" => true,
            "optional_extensions_retained" => []
          })
      },
      %{
        "id" => "receipt-profile-context-algorithm-outside",
        "surface" => "receipt.verify",
        "class" => "profile_algorithm_outside",
        "input" => %{
          "chain" => receipt_chain_input,
          "compact" => rev2_receipt.compact,
          "profile" => algorithm_profile
        },
        "expect" => invalid.("algorithm_outside_profile")
      },
      %{
        "id" => "receipt-profile-revision-only-algorithm-outside",
        "surface" => "receipt.verify",
        "class" => "profile_algorithm_outside",
        "input" => %{
          "revision_text" => chain_genesis_bytes,
          "compact" => rev1_receipt,
          "profile" => algorithm_profile
        },
        "expect" => invalid.("algorithm_outside_profile")
      },
      %{
        "id" => "receipt-profile-revision-only-revision-outside",
        "surface" => "receipt.verify",
        "class" => "profile_revision_outside",
        "input" => %{
          "revision_text" => chain_genesis_bytes,
          "compact" => rev2_receipt.compact,
          "profile" => revision_profile
        },
        "expect" => invalid.("revision_outside_profile")
      }
    ]

review_cases = [
  %{
    "id" => "json-unknown-limits-member",
    "surface" => "json.decode",
    "class" => "invalid_type",
    "input" => %{"text" => "null", "limits" => %{"cap_unregistered_limit" => 1}},
    "expect" => invalid.("invalid_limits")
  },
  %{
    "id" => "receipt-strict-chain-limits",
    "surface" => "receipt.verify",
    "class" => "maximum_plus_one",
    "input" =>
      Enum.find(cases ++ supplemental_cases, &(&1["id"] == "receipt-signed-governing-match"))[
        "input"
      ]
      |> Map.put("limits", %{"max_artifact_set_items" => 1}),
    "expect" => invalid.("limit_exceeded")
  }
]

cases =
  cases ++
    descriptor_cases ++
    revision_cases ++
    acceptance_cases ++
    termination_cases ++
    chain_cases ++
    profile_cases ++
    coverage_cases ++
    closed_claims_cases ++
    termination_effect_cases ++
    party_grouping_cases ++
    set_limit_cases ++
    price_body_cases ++
    distinct_party_cases ++
    year_zero_cases ++
    strict_digest_cases ++
    displacement_cases ++
    context_profile_cases ++
    supplemental_cases ++
    review_cases ++
    CharterAgreementProtocol.SigningPrepareCases.cases() ++
    CharterAgreementProtocol.Ed25519KeyCases.cases()

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
  "registry_digest" => ExtensionRegistry.digest() |> Digest.to_tagged(),
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
