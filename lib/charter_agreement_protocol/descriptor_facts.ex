defmodule CharterAgreementProtocol.DescriptorFacts do
  @moduledoc "Verified, view-relative facts for one party descriptor."

  @enforce_keys [
    :descriptor,
    :descriptor_digest,
    :party_id,
    :descriptor_number,
    :prev_descriptor_digest,
    :signing_key_id,
    :descriptor_position,
    :lineage
  ]
  defstruct @enforce_keys

  @type position :: :head | :superseded | :contested
  @type t :: %__MODULE__{
          descriptor: CharterAgreementProtocol.PartyDescriptor.t(),
          descriptor_digest: binary(),
          party_id: binary(),
          descriptor_number: pos_integer(),
          prev_descriptor_digest: nil | binary(),
          signing_key_id: binary(),
          descriptor_position: position(),
          lineage: [binary()]
        }
end

defmodule CharterAgreementProtocol.ForkEvidence do
  @moduledoc "Signed sibling descriptor digests retained as fork evidence."

  @enforce_keys [:kind, :sibling_descriptors]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          kind: :sibling_descriptors,
          sibling_descriptors: [binary()]
        }
end
