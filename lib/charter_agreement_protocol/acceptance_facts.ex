defmodule CharterAgreementProtocol.AcceptanceFacts do
  @moduledoc "Verified, view-relative facts for one countersignature."

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
  defstruct @enforce_keys

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
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.AcceptanceFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.AcceptanceFacts<redacted>")
end
