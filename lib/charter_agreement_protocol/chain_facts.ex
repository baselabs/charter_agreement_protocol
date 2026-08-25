defmodule CharterAgreementProtocol.ChainFacts do
  @moduledoc "Verified, redacted and view-relative structural charter-set facts."

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    DescriptorChain,
    ForkEvidence,
    RevisionFacts,
    TerminationFacts
  }

  defstruct [
    :charter_id,
    chain_topology: :linear,
    revision_facts: [],
    accepted_revision_digests: [],
    acceptance_facts: [],
    descriptor_chains: [],
    termination_facts: [],
    superseded_revision_digests: [],
    fork_evidence: [],
    not_verified: []
  ]

  @type t :: %__MODULE__{
          charter_id: nil | binary(),
          chain_topology: :linear | :forked,
          revision_facts: [RevisionFacts.t()],
          accepted_revision_digests: [binary()],
          acceptance_facts: [AcceptanceFacts.t()],
          descriptor_chains: [DescriptorChain.t()],
          termination_facts: [TerminationFacts.t()],
          superseded_revision_digests: [binary()],
          fork_evidence: [ForkEvidence.t()],
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.ChainFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.ChainFacts<redacted>")
end
