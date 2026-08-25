defmodule CharterAgreementProtocol.ReceiptFacts do
  @moduledoc "Verified, redacted and view-relative receipt cross-check facts."

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
  defstruct @enforce_keys

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
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.ReceiptFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.ReceiptFacts<redacted>")
end
