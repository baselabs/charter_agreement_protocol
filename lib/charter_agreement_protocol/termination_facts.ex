defmodule CharterAgreementProtocol.TerminationFacts do
  @moduledoc "Non-authorizing, verified, view-relative facts for one termination notice."

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
  defstruct @enforce_keys

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
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.TerminationFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.TerminationFacts<redacted>")
end
