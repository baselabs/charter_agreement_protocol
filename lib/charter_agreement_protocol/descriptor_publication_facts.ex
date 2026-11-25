defmodule CharterAgreementProtocol.DescriptorPublicationFacts do
  @moduledoc """
  Facts about a verified current and next descriptor in one supplied history.
  The facts retain the canonical publication bytes and both verified descriptors.
  CAP never authorizes.
  """

  alias CharterAgreementProtocol.{DescriptorFacts, Timestamp}

  @enforce_keys [
    :protocol_revision,
    :canonical_bytes,
    :publication_digest,
    :party_id,
    :current_descriptor,
    :next_descriptor,
    :current_descriptor_digest,
    :next_descriptor_digest,
    :current_effective_from,
    :next_effective_from,
    :commitment_status,
    :not_verified
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          protocol_revision: 8,
          canonical_bytes: binary(),
          publication_digest: binary(),
          party_id: binary(),
          current_descriptor: DescriptorFacts.t(),
          next_descriptor: DescriptorFacts.t(),
          current_descriptor_digest: binary(),
          next_descriptor_digest: binary(),
          current_effective_from: Timestamp.t(),
          next_effective_from: Timestamp.t(),
          commitment_status: :opened | :not_present,
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.DescriptorPublicationFacts do
  def inspect(_facts, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.DescriptorPublicationFacts<redacted>")
end
