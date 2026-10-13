defmodule CharterAgreementProtocol.ChainFacts do
  @moduledoc """
  What `CharterAgreementProtocol.verify_chain/5` found in one charter
  artifact set. These facts are non-authorizing and relative to the set you
  supplied: CAP cannot know about artifacts you do not hold.

  Pass this record to `CharterAgreementProtocol.governing_revision/2` to ask
  which revision governs at an instant, and to
  `CharterAgreementProtocol.verify_receipt/3` as receipt context.

  ## Fields

  - `charter_id`: the charter's id, which is the genesis revision's digest.
  - `chain_topology`: `:linear`, or `:forked` when the accepted revisions
    that nothing supersedes are not all ancestors of one newest revision.
  - `revision_facts`: one `CharterAgreementProtocol.RevisionFacts` per
    supplied revision, sorted by revision number, then digest.
  - `accepted_revision_digests`: digests of the revisions every listed party
    accepted, sorted.
  - `acceptance_facts`: one `CharterAgreementProtocol.AcceptanceFacts` per
    supplied Acceptance, sorted by Acceptance digest.
  - `descriptor_chains`: one `CharterAgreementProtocol.DescriptorChain` per
    party, sorted by party id.
  - `termination_facts`: one `CharterAgreementProtocol.TerminationFacts` per
    supplied termination notice, sorted by notice digest.
  - `superseded_revision_digests`: digests that an accepted revision lists in
    its `supersedes` member, sorted.
  - `fork_evidence`: a `CharterAgreementProtocol.ForkEvidence` for each
    signed conflict: forked descriptor chains first, then accepted sibling
    revisions, then equivocal Acceptances. Empty when there is none.
  - `not_verified`: the twelve atoms from
    `CharterAgreementProtocol.Facts.not_verified_floor/0`: `:tenancy`,
    `:live_policy`, `:authority`, `:effect_ownership`, `:execution`,
    `:billing`, `:evaluation_truth`, `:legal_validity`, `:term_satisfaction`,
    `:view_completeness`, `:counterparty_view` and `:wall_clock`.

  Digests are `"sha-256:<base64url>"` strings.

  ## Inspecting

  `inspect/2` prints `#CharterAgreementProtocol.ChainFacts<redacted>`. Read
  fields directly, or use `inspect(facts, structs: false)` while debugging.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> {:ok, facts} =
      ...>   CharterAgreementProtocol.verify_chain(
      ...>     set["revisions"],
      ...>     set["acceptances"],
      ...>     set["descriptors"],
      ...>     set["terminations"],
      ...>     CharterAgreementProtocol.Limits.default()
      ...>   )
      iex> facts
      #CharterAgreementProtocol.ChainFacts<redacted>
      iex> {facts.chain_topology, length(facts.revision_facts), length(facts.acceptance_facts)}
      {:linear, 1, 2}
      iex> facts.not_verified == CharterAgreementProtocol.Facts.not_verified_floor()
      true
  """

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

  @typedoc "Facts for one verified charter artifact set. See the module doc for each field."
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
