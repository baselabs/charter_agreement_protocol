defmodule CharterAgreementProtocol do
  @moduledoc """
  Charter Agreement Protocol.

  The implemented foundation provides strict base64url, bounded deterministic
  JSON decoding, RFC 8785 canonicalization, domain-separated tagged digests,
  typed value-free errors, table-driven artifact validation, and a
  drift-resistant conformance-corpus loader. Artifact-specific verification
  surfaces land on top of this foundation.
  """

  alias CharterAgreementProtocol.{
    Acceptance,
    AcceptanceFacts,
    ArtifactSet,
    Chain,
    ChainFacts,
    CharterRevision,
    DescriptorChain,
    DescriptorFacts,
    Limits,
    PartyDescriptor,
    TerminationFacts,
    TerminationNotice
  }

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

  @doc "Decode one canonical unsigned Charter Revision."
  @spec decode_charter_revision(term(), Limits.t()) ::
          {:ok, CharterRevision.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate decode_charter_revision(bytes, limits), to: CharterRevision, as: :decode

  @doc "Return one decoded Charter Revision's content digest."
  @spec revision_digest(CharterRevision.t()) :: binary()
  defdelegate revision_digest(revision), to: CharterRevision, as: :digest

  @doc "Verify one Acceptance against exact revision and descriptor-chain facts."
  @spec verify_acceptance(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t()) ::
          {:ok, AcceptanceFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_acceptance(compact, revision, descriptor_chain, limits),
    to: Acceptance,
    as: :verify

  @doc "Verify one termination notice against exact revision and descriptor-chain facts."
  @spec verify_termination(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t()) ::
          {:ok, TerminationFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_termination(compact, revision, descriptor_chain, limits),
    to: TerminationNotice,
    as: :verify

  @doc "Build a typed set of charter artifacts without verifying them."
  @spec build_set(term(), term(), term(), term()) ::
          {:ok, ArtifactSet.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate build_set(revisions, acceptances, terminations, descriptors),
    to: ArtifactSet,
    as: :build

  @doc "Verify a complete caller-supplied charter artifact view."
  @spec verify_chain(term(), term(), term(), term(), Limits.t()) ::
          {:ok, ChainFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_chain(revisions, acceptances, descriptors, terminations, limits),
    to: Chain,
    as: :verify

  @doc "Compute the unique governing revision in a verified view at one UTC instant."
  @spec governing_revision(term(), term()) ::
          {:ok, binary() | :contested | :none} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate governing_revision(chain_facts, at), to: Chain
end
