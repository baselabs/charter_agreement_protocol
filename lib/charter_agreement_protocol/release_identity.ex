defmodule CharterAgreementProtocol.ReleaseIdentity do
  @moduledoc """
  CAP never authorizes.

  The release-identity contract: the versioned, machine-readable facts a
  consumer binds to instead of a package number.

  Every value here is data-in-code mirrored into `priv/release-metadata.json`
  by the recorder; the release-candidate gate asserts the manifest bytes
  equal these functions. The manifest's shape is additive-only: consumers
  MUST ignore unknown members, and removing or retyping a member bumps
  `manifest_version/0` in a breaking release. Released identities are never
  mutated in place — corrections are new releases.

  ## The verification-semantics identity

  `verification_semantics/0` identifies the verdict function of the
  verification core over artifact-set inputs, quantified over all valid
  `Limits`, on a capable substrate, with no profile narrowing. It moves to a
  new value against the immediately prior release if any of these hold:
  some input that returned a verdict now returns a different verdict class
  (green to red, or red to green — admissions count), the error code for
  some input changes, any `Limits.default/0` value changes, or some input
  that returned a verdict now raises. Error subjects and details, substrate
  capability outcomes (an implementation-local diagnostic), crash-to-typed
  conversions, and facts-record fields are outside the identity.

  This is deliberately the strict definition: an identity that can hold
  constant across a change that flips the requesting consumer's evidence
  red is not an identity. The cost — a registry act (new admissions) bumps
  the value — is the honest cost; documentation-only releases hold it
  constant while the certified census digest moves, which is the whole
  point of separating the two.
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
      package_versions: ["0.4.0"],
      verification_semantics: 4,
      census_digest: "recorded-at-release",
      protocol_revisions: [1, 2, 3],
      transitions: [
        %{
          class: :verdict_narrowing,
          direction: :green_to_red,
          description:
            "PartyDescriptor effective_from gains the 1..64 string-byte floor its seven sibling timestamp members took in 0.3.0 — the last live timestamp asymmetry"
        }
      ]
    }
  ]

  @manifest_version 1
  @verification_semantics 4

  @type transition :: %{
          required(:class) => :admission | :verdict_narrowing | :resource_boundary | :typed_error,
          required(:direction) => :green_to_red | :red_to_green | :crash_to_typed,
          required(:description) => binary()
        }

  @type release_row :: %{
          required(:package_versions) => [binary()],
          required(:verification_semantics) => pos_integer(),
          required(:census_digest) => binary(),
          required(:protocol_revisions) => [pos_integer()],
          required(:transitions) => [transition()]
        }

  @doc "The release-manifest schema version. Additive-only evolution."
  @spec manifest_version() :: pos_integer()
  def manifest_version, do: @manifest_version

  @doc "The verification-semantics identity this package implements."
  @spec verification_semantics() :: pos_integer()
  def verification_semantics, do: @verification_semantics

  @doc """
  The retroactive semantics mapping for every released package.

  S1 = 0.1.0; S2 = 0.2.0–0.2.1 (revision-2 admissions); S3 = 0.3.0–0.3.2
  (ML-DSA admissions, timestamp floors, the default byte budget); S4 =
  0.4.0 (the descriptor timestamp floor). Pre-0.4.0 releases never carried
  these members: this table is CAP's documented classification of already
  released artifacts, never a rewrite of a released manifest.
  """
  @spec verification_semantics_history() :: [release_row()]
  def verification_semantics_history, do: @compatibility

  @doc """
  The machine-readable compatibility matrix: one row per semantics family.

  Each row names the package versions, the semantics identity, the certified
  census digest of that family's corpus, the protocol revisions the family
  verifies, and the enumerated verdict transitions since the prior family —
  the finite evidence the standing per-release differential gate reproduces.
  It is evidence over named inputs, not a proof of universal equivalence,
  and CAP does not claim one.
  """
  @spec compatibility() :: [release_row()]
  def compatibility, do: @compatibility

end
