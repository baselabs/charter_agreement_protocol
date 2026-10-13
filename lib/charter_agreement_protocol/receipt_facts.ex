defmodule CharterAgreementProtocol.ReceiptFacts do
  @moduledoc """
  Facts about one verified receipt, checked against the context you passed
  to `CharterAgreementProtocol.verify_receipt/3`. They are non-authorizing:
  CAP checks that the receipt names exact charter coordinates and who signed
  it, not that anything it describes happened.

  ## Fields

  - `receipt_digest`: the receipt's content digest.
  - `charter_id`: the charter id the receipt names.
  - `revision_number` and `revision_digest`: the revision the receipt names.
  - `issuing_party_role`: the role of the party that signed the receipt.
  - `agent_party_role`: the role in the receipt's `agent_party_role` member.
  - `deployment_digest`: the deployment digest the receipt names.
  - `grant_scheme`: the receipt's `grant.scheme` member, `:bap` or `:host`.
  - `grant_digest`: the receipt's `grant.grant_digest` member, or `nil` when
    absent. The `bap` scheme requires it.
  - `invocation_id`: the receipt's `invocation_id` member.
  - `decision`: the receipt's `decision` member, `:accepted` or `:rejected`.
  - `outcome`: the receipt's `outcome` member: `:effect_committed`,
    `:no_effect` or `:indeterminate`.
  - `occurred_at` and `recorded_at`: the receipt's
    `CharterAgreementProtocol.Timestamp` values. `recorded_at` is never
    before `occurred_at`.
  - `signing_key_id`: the `kid` that signed, when verified against chain
    facts. `nil` against a single revision, where no signature is checked.
  - `chain_conflict`: `:fork_evidenced` when the receipt names a revision
    that is not accepted in your view but whose number is at or below the
    newest accepted revision. Otherwise `:none`.
  - `governing_match`: the receipt's revision compared with the revision
    that governs at `occurred_at`: `:match`, `:mismatch` (including when
    nothing governs), or `:undetermined` when the view is contested or the
    context is a single revision.
  - `deployment_digest_matched`: `true` when the receipt's revision is in
    context and its `abp_bindings` bind `deployment_digest` to the agent
    role. `false` when the revision is not in your view.
  - `optional_extensions_retained`: names of every optional extension the
    receipt carries, each kept byte for byte. A registered, active namespace
    was validated against its schema; an unknown, reserved or retired one is
    kept without validation, so a name here does not prove registration.
  - `protocol_revision`: the receipt's `protocol_revision`.
  - `alg`: the JWS `alg` it was signed with, such as `"Ed25519"`.
  - `not_verified`: the twelve atoms from
    `CharterAgreementProtocol.Facts.not_verified_floor/0` (`:tenancy`,
    `:live_policy`, `:authority`, `:effect_ownership`, `:execution`,
    `:billing`, `:evaluation_truth`, `:legal_validity`, `:term_satisfaction`,
    `:view_completeness`, `:counterparty_view` and `:wall_clock`), plus
    `:signature` when verified against a single revision.

  Digests are `"sha-256:<base64url>"` strings.

  ## Inspecting

  `inspect/2` prints `#CharterAgreementProtocol.ReceiptFacts<redacted>`.
  Read fields directly, or use `inspect(facts, structs: false)` while
  debugging.
  """

  alias CharterAgreementProtocol.Timestamp

  @enforce_keys [
    :receipt_digest,
    :charter_id,
    :revision_number,
    :revision_digest,
    :issuing_party_role,
    :agent_party_role,
    :deployment_digest,
    :grant_scheme,
    :grant_digest,
    :invocation_id,
    :decision,
    :outcome,
    :occurred_at,
    :recorded_at,
    :signing_key_id,
    :chain_conflict,
    :governing_match,
    :deployment_digest_matched,
    :optional_extensions_retained,
    :not_verified
  ]
  defstruct @enforce_keys ++ [protocol_revision: nil, alg: nil]

  @typedoc "Facts for one verified receipt. See the module doc for each field."
  @type t :: %__MODULE__{
          receipt_digest: binary(),
          charter_id: binary(),
          revision_number: pos_integer(),
          revision_digest: binary(),
          issuing_party_role: binary(),
          agent_party_role: binary(),
          deployment_digest: binary(),
          grant_scheme: :bap | :host,
          grant_digest: nil | binary(),
          invocation_id: binary(),
          decision: :accepted | :rejected,
          outcome: :effect_committed | :no_effect | :indeterminate,
          occurred_at: Timestamp.t(),
          recorded_at: Timestamp.t(),
          signing_key_id: nil | binary(),
          chain_conflict: :none | :fork_evidenced,
          governing_match: :match | :mismatch | :undetermined,
          deployment_digest_matched: boolean(),
          optional_extensions_retained: [binary()],
          not_verified: [atom()],
          protocol_revision: pos_integer() | nil,
          alg: binary() | nil
        }
end

defimpl Inspect, for: CharterAgreementProtocol.ReceiptFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.ReceiptFacts<redacted>")
end
