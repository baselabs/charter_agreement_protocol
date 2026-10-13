defmodule CharterAgreementProtocol.AcceptanceFacts do
  @moduledoc """
  Facts about one verified Acceptance: one party's signed assent to one
  revision. They are non-authorizing and relative to the descriptors you
  supplied.

  `CharterAgreementProtocol.verify_acceptance/4` returns one of these, and
  `CharterAgreementProtocol.ChainFacts.acceptance_facts` holds one per
  Acceptance in a verified set.

  ## Fields

  - `acceptance`: the decoded `CharterAgreementProtocol.Acceptance`.
  - `acceptance_digest`: the Acceptance's content digest.
  - `charter_id`: the charter id the Acceptance claims.
  - `revision_number`: the number of the revision it accepts.
  - `revision_digest`: the digest of the revision it accepts.
  - `prev_revision_digest`: that revision's previous revision digest, or
    `nil` for the genesis revision.
  - `party_descriptor_digest`: the digest of the signer's Party Descriptor.
  - `party_role`: the role the signer holds in the revision, such as
    `"issuer"`.
  - `accepted_at`: the `CharterAgreementProtocol.Timestamp` the signer put in
    the claims. CAP does not compare it with any clock.
  - `signing_key_id`: the `kid` of the key that signed, active in the
    signer's descriptor.
  - `descriptor_position`: where the signer's descriptor sits in its chain:
    `:head`, `:superseded`, or `:contested` when that chain is forked. CAP
    keeps this as a fact; whether a superseded descriptor may still sign is
    your policy.
  - `protocol_revision`: the Acceptance's `protocol_revision`.
  - `alg`: the JWS `alg` it was signed with, such as `"Ed25519"`.
  - `not_verified`: the twelve atoms from
    `CharterAgreementProtocol.Facts.not_verified_floor/0`: `:tenancy`,
    `:live_policy`, `:authority`, `:effect_ownership`, `:execution`,
    `:billing`, `:evaluation_truth`, `:legal_validity`, `:term_satisfaction`,
    `:view_completeness`, `:counterparty_view` and `:wall_clock`.

  Digests are `"sha-256:<base64url>"` strings.

  ## Inspecting

  `inspect/2` prints `#CharterAgreementProtocol.AcceptanceFacts<redacted>`.
  Read fields directly, or use `inspect(facts, structs: false)` while
  debugging.
  """

  alias CharterAgreementProtocol.{Acceptance, Timestamp}

  @enforce_keys [
    :acceptance,
    :acceptance_digest,
    :charter_id,
    :revision_number,
    :revision_digest,
    :prev_revision_digest,
    :party_descriptor_digest,
    :party_role,
    :accepted_at,
    :signing_key_id,
    :descriptor_position,
    :not_verified
  ]
  defstruct @enforce_keys ++ [protocol_revision: nil, alg: nil]

  @typedoc "Facts for one verified Acceptance. See the module doc for each field."
  @type t :: %__MODULE__{
          acceptance: Acceptance.t(),
          acceptance_digest: binary(),
          charter_id: binary(),
          revision_number: pos_integer(),
          revision_digest: binary(),
          prev_revision_digest: nil | binary(),
          party_descriptor_digest: binary(),
          party_role: binary(),
          accepted_at: Timestamp.t(),
          signing_key_id: binary(),
          descriptor_position: :head | :superseded | :contested,
          not_verified: [atom()],
          protocol_revision: pos_integer() | nil,
          alg: binary() | nil
        }
end

defimpl Inspect, for: CharterAgreementProtocol.AcceptanceFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.AcceptanceFacts<redacted>")
end
