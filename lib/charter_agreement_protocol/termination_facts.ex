defmodule CharterAgreementProtocol.TerminationFacts do
  @moduledoc """
  Facts about one verified termination notice. They are non-authorizing: they
  show that a listed party signed a listed reason and an effective time, not
  that the notice was delivered or has legal effect.

  `CharterAgreementProtocol.verify_termination/4` returns one of these, and
  `CharterAgreementProtocol.ChainFacts.termination_facts` holds one per
  notice in a verified set. A notice ends governance only when the revision it
  names governs at its `effective_at`; `CharterAgreementProtocol.governing_revision/2`
  applies that rule.

  ## Fields

  - `termination`: the decoded `CharterAgreementProtocol.TerminationNotice`.
  - `termination_digest`: the notice's content digest.
  - `charter_id`: the charter id the notice claims.
  - `governing_revision_digest`: the revision the notice says it ends.
  - `party_descriptor_digest`: the digest of the signer's Party Descriptor.
  - `party_role`: the role the signer holds in that revision.
  - `reason_code`: the reason, one of the codes the revision's
    `termination_rules` list.
  - `effective_at`: the `CharterAgreementProtocol.Timestamp` the notice takes
    effect. CAP does not check whether that time has come.
  - `issued_at`: the `CharterAgreementProtocol.Timestamp` the signer gave for
    issuing it. It is never after `effective_at`.
  - `detail_digest`: an opaque digest the signer attached, or `nil` when the
    notice names none.
  - `signing_key_id`: the `kid` of the key that signed, active in the
    signer's descriptor.
  - `descriptor_position`: where the signer's descriptor sits in its chain:
    `:head`, `:superseded` or `:contested`.
  - `protocol_revision`: the notice's `protocol_revision`.
  - `alg`: the JWS `alg` it was signed with, such as `"Ed25519"`.
  - `not_verified`: the twelve atoms from
    `CharterAgreementProtocol.Facts.not_verified_floor/0`: `:tenancy`,
    `:live_policy`, `:authority`, `:effect_ownership`, `:execution`,
    `:billing`, `:evaluation_truth`, `:legal_validity`, `:term_satisfaction`,
    `:view_completeness`, `:counterparty_view` and `:wall_clock`.

  Digests are `"sha-256:<base64url>"` strings.

  ## Inspecting

  `inspect/2` prints `#CharterAgreementProtocol.TerminationFacts<redacted>`.
  Read fields directly, or use `inspect(facts, structs: false)` while
  debugging.
  """

  alias CharterAgreementProtocol.{TerminationNotice, Timestamp}

  @enforce_keys [
    :termination,
    :termination_digest,
    :charter_id,
    :governing_revision_digest,
    :party_descriptor_digest,
    :party_role,
    :reason_code,
    :effective_at,
    :issued_at,
    :detail_digest,
    :signing_key_id,
    :descriptor_position,
    :not_verified
  ]
  defstruct @enforce_keys ++ [protocol_revision: nil, alg: nil]

  @typedoc "Facts for one verified termination notice. See the module doc for each field."
  @type t :: %__MODULE__{
          termination: TerminationNotice.t(),
          termination_digest: binary(),
          charter_id: binary(),
          governing_revision_digest: binary(),
          party_descriptor_digest: binary(),
          party_role: binary(),
          reason_code: binary(),
          effective_at: Timestamp.t(),
          issued_at: Timestamp.t(),
          detail_digest: nil | binary(),
          signing_key_id: binary(),
          descriptor_position: :head | :superseded | :contested,
          not_verified: [atom()],
          protocol_revision: pos_integer() | nil,
          alg: binary() | nil
        }
end

defimpl Inspect, for: CharterAgreementProtocol.TerminationFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.TerminationFacts<redacted>")
end
