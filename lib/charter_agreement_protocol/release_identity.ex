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

  `verification_semantics/0` identifies how verification decides: for every
  artifact-set input, under any valid `CharterAgreementProtocol.Limits`, on
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
      package_versions: ["0.6.0"],
      verification_semantics: 6,
      census_digest: "sha-256:2-t12PxqWcNhr1MBdhlFkwRhN5K_5pYN5m7Z-sxafmQ",
      protocol_revisions: [1, 2, 3],
      transitions: [
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
            "Malformed caller-built context field types use invalid_type consistently where receipt_invalid or descriptor_chain_invalid previously named an unusable context"
        }
      ]
    }
  ]

  @manifest_version 1
  @verification_semantics 6

  @typedoc "One verdict change between releases."
  @type transition :: %{
          required(:class) =>
            :admission
            | :verdict_narrowing
            | :resource_boundary
            | :typed_error
            | :error_code_change,
          required(:direction) => :green_to_red | :red_to_green | :crash_to_typed | :red_to_red,
          required(:description) => binary()
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
  direction and what changed. The rows are evidence over the named corpus
  inputs, not a proof that every possible input behaves the same.
  """
  @spec compatibility() :: [release_row()]
  def compatibility, do: @compatibility
end
