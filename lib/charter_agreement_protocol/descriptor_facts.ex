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
    :lineage,
    :not_verified
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
          lineage: [binary()],
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.DescriptorFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.DescriptorFacts<redacted>")
end

defmodule CharterAgreementProtocol.ForkEvidence do
  @moduledoc "Signed descriptor, revision, or acceptance conflict evidence."

  @enforce_keys [:kind, :not_verified]
  defstruct [
    :kind,
    sibling_descriptors: [],
    revision_digests: [],
    acceptance_digests: [],
    not_verified: []
  ]

  @type t :: %__MODULE__{
          kind: :sibling_descriptors | :sibling_revisions | :equivocal_acceptances,
          sibling_descriptors: [binary()],
          revision_digests: [binary()],
          acceptance_digests: [binary()],
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.ForkEvidence do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.ForkEvidence<redacted>")
end
