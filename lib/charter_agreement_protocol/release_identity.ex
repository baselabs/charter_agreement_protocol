defmodule CharterAgreementProtocol.ReleaseIdentity do
  @moduledoc """
  The release facts a consumer can pin instead of a package version. They
  are non-authorizing release metadata.

  Every value here is also written to `priv/release-metadata.json`, and the
  release check confirms the file matches these functions. The manifest only
  grows: ignore members you do not know. Removing or retyping a member
  changes `manifest_version/0` in a breaking release. A released identity is
  never edited; a correction is a new release.

  ## Verification semantics

  `verification_semantics/0` identifies verification behavior for every
  artifact set and caller-built context, under any valid
  `CharterAgreementProtocol.Limits`, on
  a runtime that supports every algorithm, with no profile. The value
  changes from one release to the next when any of these happen:

  - an input that got a verdict now gets the other verdict (valid to
    invalid, or invalid to valid, including newly admitted algorithms or
    revisions);
  - the error code for an input changes;
  - a `CharterAgreementProtocol.Limits.default/0` value changes;
  - an input that got a verdict now raises.

  These do not change it: error subjects and details, runtime capability
  results, a crash that becomes a typed error, and facts-record fields.

  Store this value with your verification results. An unchanged value after
  an upgrade means the release declares no verdict or error-code change for
  any input; `compatibility/0` holds the corpus evidence. A release that only
  adds conformance cases keeps the value and records a new corpus digest.
  """

  @compatibility [
    %{
      package_versions: ["0.1.0"],
      verification_semantics: 1,
      census_digest: "sha-256:ORUavQBNHFZG8XEAsunlHaHXDMMaNMW2ggImIotd-n4",
      protocol_revisions: [1],
      transitions: []
    },
    %{
      package_versions: ["0.2.0", "0.2.1"],
      verification_semantics: 2,
      census_digest: "sha-256:nLE8UwbYxyIRG147jhJoQLHf0RpsA4dw8X5ATpJvKK8",
      protocol_revisions: [1, 2],
      transitions: [
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Revision-2 artifacts and the Ed25519 name admitted at revision 2 (RFC 9864 alg-name bundle); legacy (EdDSA, 1) fixtures stay literally pinned"
        }
      ]
    },
    %{
      package_versions: ["0.3.0", "0.3.1", "0.3.2"],
      verification_semantics: 3,
      census_digest: "sha-256:9t3IsUcPMqtZiJE9wlYchjDJNoSpO4RbOte26RqgEqc",
      protocol_revisions: [1, 2, 3],
      transitions: [
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "ML-DSA-44/65/87 admitted at revision 3; (EdDSA, 3) admitted; mixed-algorithm key sets legal (ml-dsa-admission ADR)"
        },
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "Seven timestamp members gained a 1..64 string-byte floor: long-fraction spellings the 0.2.x codec accepted now reject at the schema stage"
        },
        %{
          class: :resource_boundary,
          direction: :green_to_red,
          description:
            "max_artifact_set_bytes added to Limits (64 MiB default): previously verifiable oversized views now limit_exceeded under default limits"
        },
        %{
          class: :typed_error,
          direction: :crash_to_typed,
          description: "Improper-list inputs return typed errors instead of raising ArgumentError"
        }
      ]
    },
    %{
      package_versions: ["0.4.0", "0.4.1"],
      verification_semantics: 4,
      census_digest: "sha-256:bp_w7EUDVgwU5hNWLwUrIVeWKSas3xbaLLcN6Sn6Ev8",
      protocol_revisions: [1, 2, 3],
      transitions: [
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "PartyDescriptor effective_from gains the 1..64 string-byte floor its seven sibling timestamp members took in 0.3.0 — the last live timestamp asymmetry"
        }
      ]
    },
    %{
      package_versions: ["0.5.0"],
      verification_semantics: 5,
      census_digest: "sha-256:ivfIdXDtMDpq5ElpaVgRr8gqRVXsmMMr2oeXyuH4bw4",
      protocol_revisions: [1, 2, 3],
      transitions: [
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "A charter's parties must be distinct parties: a revision naming one descriptor for two roles rejects (revision_invalid), and a chain view whose revision parties resolve to one descriptor history, or that holds a history no revision names, rejects (chain_invalid)"
        }
      ]
    },
    %{
      package_versions: ["0.6.0", "1.0.0"],
      verification_semantics: 6,
      census_digest: "sha-256:ZpJFSZnj2-4PGcOdggkwK62YFtCRmQfr_7kKnuwtKL0",
      protocol_revisions: [1, 2, 3],
      transitions: [
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "Ed25519 public keys are fully decoded on admission: signatures using the identity and order-two negative-zero encodings return signature_invalid instead of ok; keys with no curve point are rejected, and signing preparation returns signing_key_invalid for all three encodings instead of ok"
        },
        %{
          class: :typed_error,
          direction: :crash_to_typed,
          description:
            "Limits structs with missing fields and profiles with improper algorithm lists return invalid_limits or invalid_profile instead of raising"
        },
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "Every retained and descriptive field type in caller-built revisions, descriptor facts, descriptor chains and chain facts is checked; malformed fields that 0.5.0 ignored and accepted now return invalid_type"
        },
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "Caller-built receipt revisions with a non-integer revision_number and chain facts with an invalid chain_topology or non-atom not_verified entries now return invalid_type instead of ok"
        },
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "Caller-built acceptance and termination descriptor chains with an invalid topology, and revisions with non-binary supersedes entries, now return invalid_type instead of ok"
        },
        %{
          class: :typed_error,
          direction: :crash_to_typed,
          description:
            "Malformed retained context fields, including improper lineage lists and non-binary envelope message or signature fields, return invalid_type instead of raising"
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Wrong context terms and malformed caller-built context field types use invalid_type consistently where receipt_invalid or descriptor_chain_invalid previously named an unusable context"
        }
      ]
    },
    %{
      package_versions: ["1.1.0"],
      verification_semantics: 7,
      census_digest: "sha-256:NBhh3sS6mPIeMhRVAOrcbNJRc3QxmSnxgpvhf4-aHQg",
      protocol_revisions: [1, 2, 3, 8],
      transitions: [
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "Legacy successor eligibility requires an accepted predecessor. Signing also " <>
            "requires accepted supersession targets.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "valid",
              to: "receipt_claims_mismatch",
              cases: ~w(
                receipt-legacy-successor-without-accepted-parent
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "valid",
              to: "signing_refused",
              cases: ~w(
                signing-legacy-successor-without-accepted-parent
                signing-legacy-supersession-target-still-proposed
                signing-termination-without-accepted-predecessor
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "The TypeScript verifier checks list items and bounds in list order.",
          witnesses: [
            %{
              baselines: ["npm:1.0.0"],
              from: "limit_exceeded",
              to: "invalid_type",
              cases: ~w(
                chain-item-type-before-item-limit
                chain-item-type-before-list-byte-limit
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "TypeScript compact assembly checks for an algorithm field before registry " <>
            "lookup.",
          witnesses: [
            %{
              baselines: ["npm:1.0.0"],
              from: "algorithm_unsupported",
              to: "signing_input_invalid",
              cases: ~w(
                api-assemble-missing-alg
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Revision-8 descriptor histories reach topology or commitment validation.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "descriptor_chain_invalid",
              to: "valid",
              cases: ~w(
                descriptor-publication-chain-fork
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Revision-8 descriptors reach key and commitment checks.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "valid",
              cases: ~w(
                descriptor-publication-successor
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Revision-8 descriptors reach key and commitment checks.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "descriptor_commitment_mismatch",
              cases: ~w(
                descriptor-publication-different-active
                descriptor-publication-downgrade
                descriptor-publication-extra-active
                descriptor-publication-missing-active
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "descriptor_invalid",
              cases: ~w(
                descriptor-publication-active-material-alias
                descriptor-publication-noncanonical-commitment
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Descriptor signing checks the admitted revision-8 predecessor and its key " <>
            "commitment.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "valid",
              cases: ~w(
                descriptor-publication-sign-successor
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Descriptor signing checks the admitted revision-8 predecessor and its key " <>
            "commitment.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "descriptor_commitment_mismatch",
              cases: ~w(
                descriptor-publication-sign-opening-mismatch
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "The TypeScript verifier evaluates the acceptance list before checking " <>
            "duplicate coordinates.",
          witnesses: [
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "acceptance_claims_mismatch",
              cases: ~w(
                chain-legacy-duplicate-before-claims-binding
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "acceptance_invalid",
              cases: ~w(
                chain-legacy-duplicate-before-claims-coordinates
                chain-legacy-duplicate-before-key-resolution
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "algorithm_outside_profile",
              cases: ~w(
                chain-legacy-duplicate-before-algorithm-profile
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "compact_invalid",
              cases: ~w(
                chain-malformed-vote-before-legacy-duplicate
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "constraint_violation",
              cases: ~w(
                chain-legacy-duplicate-before-claims-constraint
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "invalid_type",
              cases: ~w(
                chain-legacy-duplicate-before-claims-type
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "limit_exceeded",
              cases: ~w(
                chain-legacy-duplicate-before-compact-limit
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "missing_required",
              cases: ~w(
                chain-legacy-duplicate-before-claims-required
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "non_canonical_bytes",
              cases: ~w(
                chain-legacy-duplicate-before-payload-bytes
                chain-legacy-duplicate-before-payload-syntax
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "protected_header_invalid",
              cases: ~w(
                chain-legacy-duplicate-before-protected-type
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "revision_outside_profile",
              cases: ~w(
                chain-legacy-duplicate-before-revision-profile
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "signature_invalid",
              cases: ~w(
                chain-legacy-duplicate-before-signature-encoding
                chain-legacy-duplicate-before-signature-length
                chain-legacy-duplicate-before-signature-validity
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "timestamp_invalid",
              cases: ~w(
                chain-legacy-duplicate-before-claims-timestamp
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "chain_invalid",
              to: "unknown_member",
              cases: ~w(
                chain-legacy-duplicate-before-claims-unknown
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "The chain-expanded-histories cases and " <>
            "chain-many-histories-first-party-error expose errors past the old history " <>
            "count.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "acceptance_claims_mismatch",
              cases: ~w(
                chain-expanded-histories-before-acceptance-binding
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "acceptance_invalid",
              cases: ~w(
                chain-expanded-histories-before-acceptance-claims-coordinates
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "algorithm_outside_profile",
              cases: ~w(
                chain-expanded-histories-before-artifact-profile
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "cardinality_violation",
              cases: ~w(
                chain-expanded-histories-before-revision-cardinality-violation
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "compact_invalid",
              cases: ~w(
                chain-expanded-histories-before-acceptance-compact
                chain-expanded-histories-before-termination-compact
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "constraint_violation",
              cases: ~w(
                chain-expanded-histories-before-acceptance-claims-constraint
                chain-expanded-histories-before-revision-constraint-violation
                chain-expanded-histories-before-termination-claims-constraint
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "cross_field_invalid",
              cases: ~w(
                chain-expanded-histories-before-revision-cross-field-invalid
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "descriptor_chain_invalid",
              cases: ~w(
                chain-expanded-histories-before-history-shape
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "descriptor_key_invalid",
              cases: ~w(
                chain-many-histories-first-party-error
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "duplicate_member",
              cases: ~w(
                chain-expanded-histories-before-revision-duplicate-member
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "extension_criticality_conflict",
              cases: ~w(
                chain-expanded-histories-before-revision-extension-criticality-conflict
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "extension_duplicate",
              cases: ~w(
                chain-expanded-histories-before-revision-extension-duplicate
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "extension_namespace_invalid",
              cases: ~w(
                chain-expanded-histories-before-revision-extension-namespace-invalid
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "extension_retired",
              cases: ~w(
                chain-expanded-histories-before-revision-extension-retired
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "extension_scope_invalid",
              cases: ~w(
                chain-expanded-histories-before-revision-extension-scope-invalid
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "extension_unknown_critical",
              cases: ~w(
                chain-expanded-histories-before-revision-extension-unknown-critical
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "invalid_syntax",
              cases: ~w(
                chain-expanded-histories-before-revision-syntax
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "invalid_type",
              cases: ~w(
                chain-expanded-histories-before-acceptance-claims-type
                chain-expanded-histories-before-revision-invalid-type
                chain-expanded-histories-before-termination-claims-type
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "limit_exceeded",
              cases: ~w(
                chain-expanded-histories-before-revision-byte-limit
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "missing_required",
              cases: ~w(
                chain-expanded-histories-before-acceptance-claims-required
                chain-expanded-histories-before-revision-missing-required
                chain-expanded-histories-before-termination-claims-required
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "nested_invalid",
              cases: ~w(
                chain-expanded-histories-before-revision-nested-invalid
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "non_canonical_bytes",
              cases: ~w(
                chain-expanded-histories-before-revision-non-canonical-bytes
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "protected_header_invalid",
              cases: ~w(
                chain-expanded-histories-before-acceptance-header
                chain-expanded-histories-before-termination-header
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "revision_invalid",
              cases: ~w(
                chain-expanded-histories-before-revision-revision-invalid
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "revision_outside_profile",
              cases: ~w(
                chain-expanded-histories-before-revision-profile
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "signature_invalid",
              cases: ~w(
                chain-expanded-histories-before-acceptance-signature
                chain-expanded-histories-before-termination-signature
                chain-expanded-histories-before-termination-signature-length
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "termination_claims_mismatch",
              cases: ~w(
                chain-expanded-histories-before-termination-binding
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "termination_invalid",
              cases: ~w(
                chain-expanded-histories-before-termination-claims-coordinates
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "timestamp_invalid",
              cases: ~w(
                chain-expanded-histories-before-acceptance-claims-timestamp
                chain-expanded-histories-before-revision-timestamp-invalid
                chain-expanded-histories-before-termination-claims-timestamp
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "trailing_bytes",
              cases: ~w(
                chain-expanded-histories-before-revision-trailing
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "unknown_member",
              cases: ~w(
                chain-expanded-histories-before-acceptance-claims-unknown
                chain-expanded-histories-before-revision-unknown-member
                chain-expanded-histories-before-termination-claims-unknown
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "The TypeScript verifier finishes descendants before the next descriptor " <>
            "branch.",
          witnesses: [
            %{
              baselines: ["npm:1.0.0"],
              from: "revision_outside_profile",
              to: "descriptor_chain_invalid",
              cases: ~w(
                chain-history-descendant-before-next-branch
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Invalid UTC calendar components return a governing input error before " <>
            "conversion.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0"],
              from: "timestamp_invalid",
              to: "governing_invalid",
              cases: ~w(
                api-governing-invalid-day
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Capability profiles recognize revision 8 as a range endpoint.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "invalid_profile",
              to: "valid",
              cases: ~w(
                chain-profile-endpoint-eight-admits-legacy-view
              )
            }
          ]
        },
        %{
          class: :unsupported_in_baseline,
          direction: :baseline_unsupported,
          description:
            "Published runners cannot express unsigned descriptor publication " <>
            "verification.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "algorithm_outside_profile",
              cases: ~w(
                descriptor-publication-algorithm-profile
                descriptor-publication-mldsa-policy
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "descriptor_commitment_mismatch",
              cases: ~w(
                descriptor-publication-opening-mismatch
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "descriptor_publication_invalid",
              cases: ~w(
                descriptor-publication-duplicate
                descriptor-publication-equal-effective-time
                descriptor-publication-missing-genesis
                descriptor-publication-non-direct
                descriptor-publication-noncanonical
                descriptor-publication-reversed
                descriptor-publication-signed-fork
                descriptor-publication-unknown-member
                descriptor-publication-wrong-current
                descriptor-publication-wrong-party
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "invalid_type",
              cases: ~w(
                descriptor-publication-type
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "limit_exceeded",
              cases: ~w(
                descriptor-publication-artifact-limit
                descriptor-publication-compact-byte-limit
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "revision_outside_profile",
              cases: ~w(
                descriptor-publication-document-profile
                descriptor-publication-history-profile
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "signature_invalid",
              cases: ~w(
                descriptor-publication-corrupt-signature
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "valid",
              cases: ~w(
                descriptor-publication-legacy-history
                descriptor-publication-mldsa-opening
                descriptor-publication-opened
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Set verification applies revision-8 roster, assignment, predecessor, and " <>
            "vote rules.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "valid",
              cases: ~w(
                assignment-all-parties-assented
                assignment-all-roles-at-once
                assignment-proposed-missing-assignor
                assignment-proposed-missing-remaining-party
                quorum-genesis-met
                quorum-genesis-pending
                quorum-narrowed-pending
                quorum-narrowed-predecessor-role
                quorum-no-accepted-ancestor
                quorum-termination-duplicate-role
                quorum-termination-ineligible-role
                quorum-termination-instants-stay-separate
                quorum-termination-reasons-stay-separate
                quorum-termination-two-roles
                quorum-unsigned-hop-cannot-lower-threshold
                quorum-unsigned-predecessor-blocks-governance
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "valid",
              cases: ~w(
                assignment-mldsa65-revision-eight-complete
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "valid",
              cases: ~w(
                quorum-mixed-accepted-predecessors
                quorum-mixed-accepted-predecessors-governing
                quorum-mixed-unsigned-genesis
                quorum-mixed-unsigned-genesis-governing
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Set verification applies revision-8 roster, assignment, predecessor, and " <>
            "vote rules.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "compact_invalid",
              cases: ~w(
                assignment-malformed-vote-before-duplicate
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "chain_invalid",
              cases: ~w(
                quorum-revision-downgrade
                quorum-roster-history-missing
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "signing_refused",
              cases: ~w(
                signing-quorum-legacy-hop-without-predecessor
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Revision-8 quorum thresholds are checked for integer tokens ahead of " <>
            "canonical bytes and schema checks.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "missing_required",
              to: "invalid_type",
              cases: ~w(
                charter-revision-termination-quorum-fractional-threshold
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "non_canonical_bytes",
              to: "invalid_type",
              cases: ~w(
                charter-revision-acceptance-quorum-integral-float
                charter-revision-assignment-quorum-integral-float
                charter-revision-termination-quorum-integral-float
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "invalid_type",
              cases: ~w(
                charter-revision-acceptance-quorum-fractional-threshold
                charter-revision-assignment-quorum-fractional-threshold
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Receipt verification resolves the issuing role in a quorum or assignment " <>
            "view.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "valid",
              cases: ~w(
                assignment-receipt-contested-holder
                assignment-receipt-latest-holder-after-close
                assignment-receipt-new-holder
                assignment-receipt-predecessor-resumes
                receipt-matches-accepted-quorum
                signing-receipt-revision-eight-chain
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Receipt verification resolves the issuing role in a quorum or assignment " <>
            "view.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "chain_invalid",
              to: "receipt_claims_mismatch",
              cases: ~w(
                assignment-receipt-expired-holder
                assignment-receipt-former-holder
                assignment-receipt-former-holder-after-close
              )
            }
          ]
        },
        %{
          class: :typed_error,
          direction: :crash_to_typed,
          description:
            "Incomplete caller-built host records return typed errors through public " <>
            "verification and signing.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0"],
              from: "raised",
              to: "acceptance_equivocation_invalid",
              cases: ~w(
                api-equivocation-missing-digest
              )
            },
            %{
              baselines: ["hex:1.0.0"],
              from: "raised",
              to: "governing_invalid",
              cases: ~w(
                api-governing-missing-year
              )
            },
            %{
              baselines: ["hex:1.0.0"],
              from: "raised",
              to: "invalid_type",
              cases: ~w(
                api-descriptor-digest-missing-envelope
                api-revision-digest-missing-bytes
                api-signing-set-missing-list
              )
            },
            %{
              baselines: ["hex:1.0.0"],
              from: "raised",
              to: "signing_input_invalid",
              cases: ~w(
                api-assemble-missing-alg
              )
            }
          ]
        },
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "Caller-built host records must contain valid fields for equivocation, " <>
            "governing queries, and signing claims.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0"],
              from: "valid",
              to: "acceptance_equivocation_invalid",
              cases: ~w(
                api-equivocation-nil-digest
              )
            },
            %{
              baselines: ["hex:1.0.0"],
              from: "valid",
              to: "governing_invalid",
              cases: ~w(
                api-governing-nil-zone-abbreviation
              )
            },
            %{
              baselines: ["hex:1.0.0"],
              from: "valid",
              to: "signing_input_invalid",
              cases: ~w(
                api-signing-claims-enumerable-struct
              )
            }
          ]
        },
        %{
          class: :unsupported_in_baseline,
          direction: :baseline_unsupported,
          description:
            "Published signing entry points cannot express a marked replacement " <>
            "operation.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "acceptance_claims_mismatch",
              cases: ~w(
                signing-assignment-wrong-assignor-binding
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "signing_refused",
              cases: ~w(
                signing-assignment-empty-claims
                signing-assignment-marker-required
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unsupported",
              to: "valid",
              cases: ~w(
                signing-assignment-departing-party
                signing-mldsa65-assignment-assignor
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Revision-8 charter decoding admits the roster and quorum schema and checks " <>
            "rule semantics.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "valid",
              cases: ~w(
                quorum-three-party-roster
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Revision-8 charter decoding admits the roster and quorum schema and checks " <>
            "rule semantics.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "missing_required",
              cases: ~w(
                charter-revision-replacement-container-missing-required
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "revision_invalid",
              cases: ~w(
                assignment-assent-role-outside-candidate-rule
                assignment-role-outside-candidate-rule
                quorum-arbiter-outside-acceptance-rule
                quorum-nonstring-role
                quorum-roles-are-ordered
                quorum-threshold-exceeds-roster
                quorum-votes-must-be-distinct
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "The TypeScript verifier preserves the initial descriptor signature or key " <>
            "error.",
          witnesses: [
            %{
              baselines: ["npm:1.0.0"],
              from: "descriptor_chain_invalid",
              to: "descriptor_key_invalid",
              cases: ~w(
                chain-root-key-error-before-revision
              )
            },
            %{
              baselines: ["npm:1.0.0"],
              from: "descriptor_chain_invalid",
              to: "signature_invalid",
              cases: ~w(
                chain-root-signature-before-revision
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Signing preparation admits revision-8 acceptance and termination emission " <>
            "and checks replacement intent.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "signing_input_invalid",
              to: "valid",
              cases: ~w(
                signing-assignment-incoming-party
                signing-mldsa65-quorum-acceptance
                signing-mldsa65-quorum-termination
                signing-quorum-accepted-supersession-target
                signing-quorum-predecessor-role
                signing-quorum-termination-second-role
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Signing preparation admits revision-8 acceptance and termination emission " <>
            "and checks replacement intent.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "signing_input_invalid",
              to: "signing_refused",
              cases: ~w(
                signing-assignment-marker-unexpected
                signing-legacy-ordinary-acceptance-with-marker
                signing-quorum-ineligible-termination-role
                signing-quorum-proposed-supersession-target
                signing-quorum-unaccepted-predecessor
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Bare revision-8 receipt verification admits descriptive context. " <>
            "Preparation requires a verified set.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "valid",
              cases: ~w(
                receipt-bare-revision-eight-descriptive
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Bare revision-8 receipt verification admits descriptive context. " <>
            "Preparation requires a verified set.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "protected_header_invalid",
              cases: ~w(
                receipt-rejects-revision-eight-envelope
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "signing_refused",
              cases: ~w(
                signing-receipt-bare-revision-eight-refused
              )
            }
          ]
        },
        %{
          class: :admission,
          direction: :red_to_green,
          description:
            "Standalone vote verification can decode the revision-8 charter and reach " <>
            "the vote checks.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "valid",
              cases: ~w(
                assignment-assignor-pairing
                assignment-mldsa65-revision-eight-assignor
                quorum-mldsa65-revision-eight-termination
                quorum-mldsa65-revision-eight-vote
                quorum-termination-pairing
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Standalone vote verification can decode the revision-8 charter and reach " <>
            "the vote checks.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "acceptance_claims_mismatch",
              cases: ~w(
                assignment-rejects-assignee-marker
                assignment-rejects-marker-role-mismatch
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "acceptance_invalid",
              cases: ~w(
                quorum-acceptance-envelope-unresolved-key
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "signature_invalid",
              cases: ~w(
                quorum-acceptance-envelope-signature-validity
                quorum-termination-envelope-signature-validity
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "unknown_member",
              to: "termination_invalid",
              cases: ~w(
                quorum-termination-envelope-unresolved-key
              )
            }
          ]
        },
        %{
          class: :error_code_change,
          direction: :red_to_red,
          description:
            "Revision-8 vote envelopes reach signature length, claims validation and " <>
            "binding.",
          witnesses: [
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "acceptance_claims_mismatch",
              cases: ~w(
                quorum-acceptance-rejects-legacy-binding
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "acceptance_invalid",
              cases: ~w(
                quorum-acceptance-envelope-claims-coordinates
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "constraint_violation",
              cases: ~w(
                quorum-acceptance-envelope-claims-constraint
                quorum-termination-envelope-claims-constraint
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "invalid_type",
              cases: ~w(
                quorum-acceptance-envelope-claims-type
                quorum-termination-envelope-claims-type
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "missing_required",
              cases: ~w(
                quorum-acceptance-envelope-claims-required
                quorum-termination-envelope-claims-required
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "signature_invalid",
              cases: ~w(
                quorum-acceptance-envelope-signature-length
                quorum-termination-envelope-signature-length
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "termination_claims_mismatch",
              cases: ~w(
                quorum-termination-rejects-legacy-binding
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "termination_invalid",
              cases: ~w(
                quorum-termination-envelope-claims-coordinates
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "timestamp_invalid",
              cases: ~w(
                quorum-acceptance-envelope-claims-timestamp
                quorum-termination-envelope-claims-timestamp
              )
            },
            %{
              baselines: ["hex:1.0.0", "npm:1.0.0"],
              from: "protected_header_invalid",
              to: "unknown_member",
              cases: ~w(
                quorum-acceptance-envelope-claims-unknown
                quorum-termination-envelope-claims-unknown
              )
            }
          ]
        }
      ]
    }
  ]

  @manifest_version 1
  @verification_semantics 7

  @typedoc "One verdict change between releases."
  @type transition :: %{
          required(:class) =>
            :admission
            | :verdict_narrowing
            | :resource_boundary
            | :typed_error
            | :error_code_change
            | :unsupported_in_baseline,
          required(:direction) =>
            :green_to_red | :red_to_green | :crash_to_typed | :red_to_red | :baseline_unsupported,
          required(:description) => binary(),
          optional(:witnesses) => [witness()]
        }

  @typedoc "Case IDs and exact normalized outcomes for named published baselines."
  @type witness :: %{
          baselines: [binary()],
          cases: [binary()],
          from: binary(),
          to: binary()
        }

  @typedoc "One row of the compatibility table."
  @type release_row :: %{
          required(:package_versions) => [binary()],
          required(:verification_semantics) => pos_integer(),
          required(:census_digest) => binary(),
          required(:protocol_revisions) => [pos_integer()],
          required(:transitions) => [transition()]
        }

  @doc "The release manifest's schema version. New members never change it."
  @spec manifest_version() :: pos_integer()
  def manifest_version, do: @manifest_version

  @doc "The verification-semantics value this package implements. See the module doc."
  @spec verification_semantics() :: pos_integer()
  def verification_semantics, do: @verification_semantics

  @doc """
  The verification-semantics value of every released package.

  Each row lists package versions, their semantics value, the digest of
  their conformance corpus, the protocol revisions they verify, and the
  verdict changes since the previous row. Releases before the manifest
  existed are included as CAP's classification of what they already did;
  their published manifests are not rewritten.
  """
  @spec verification_semantics_history() :: [release_row()]
  def verification_semantics_history, do: @compatibility

  @doc """
  The compatibility table: one row per conformance corpus.

  One semantics value can span several rows. A release that adds cases
  without changing any verdict keeps the semantics value and adds a row with
  an empty `transitions` list. Each transition names its class, its
  direction and what changed. New rows name the case IDs and outcomes that
  must differ when replayed under the published baselines. The evidence is
  finite and covers the named inputs.
  """
  @spec compatibility() :: [release_row()]
  def compatibility, do: @compatibility
end
