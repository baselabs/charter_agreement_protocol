defmodule CharterAgreementProtocol.RevisionFacts do
  @moduledoc "Verified, redacted set facts for one Charter Revision."

  alias CharterAgreementProtocol.{AcceptanceFacts, CharterRevision}

  defstruct [
    :revision,
    :revision_digest,
    :charter_id,
    :revision_number,
    :prev_revision_digest,
    acceptance_facts: [],
    acceptance_digests: [],
    acceptance_status: :proposed,
    not_verified: []
  ]

  @type t :: %__MODULE__{
          revision: CharterRevision.t(),
          revision_digest: binary(),
          charter_id: binary(),
          revision_number: pos_integer(),
          prev_revision_digest: nil | binary(),
          acceptance_facts: [AcceptanceFacts.t()],
          acceptance_digests: [binary()],
          acceptance_status: :proposed | :accepted,
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.RevisionFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.RevisionFacts<redacted>")
end
