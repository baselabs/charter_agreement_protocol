defmodule CharterAgreementProtocol do
  @moduledoc """
  Charter Agreement Protocol.

  The implemented foundation provides strict base64url, bounded deterministic
  JSON decoding, RFC 8785 canonicalization, domain-separated tagged digests,
  typed value-free errors, table-driven artifact validation, and a
  drift-resistant conformance-corpus loader. Artifact-specific verification
  surfaces land on top of this foundation.
  """

  alias CharterAgreementProtocol.{DescriptorChain, DescriptorFacts, Limits, PartyDescriptor}

  @doc "Decode one canonical attached Party Descriptor."
  @spec decode_party_descriptor(term(), Limits.t()) ::
          {:ok, PartyDescriptor.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate decode_party_descriptor(compact, limits), to: PartyDescriptor, as: :decode

  @doc "Return one decoded Party Descriptor's content digest."
  @spec descriptor_digest(PartyDescriptor.t()) :: binary()
  defdelegate descriptor_digest(descriptor), to: PartyDescriptor, as: :digest

  @doc "Verify one Party Descriptor at genesis or against a verified predecessor."
  @spec verify_descriptor(term(), nil | DescriptorFacts.t(), Limits.t()) ::
          {:ok, DescriptorFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_descriptor(compact, predecessor, limits), to: PartyDescriptor, as: :verify

  @doc "Verify a complete in-view descriptor chain and retain fork evidence."
  @spec verify_descriptor_chain(term(), Limits.t()) ::
          {:ok, DescriptorChain.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_descriptor_chain(compacts, limits), to: DescriptorChain, as: :verify
end
