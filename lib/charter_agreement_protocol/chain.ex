defmodule CharterAgreementProtocol.Chain do
  @moduledoc """
  CAP never authorizes.

  Pure set-level charter verification and view-relative governing computation.

  Set verification re-verifies every artifact and reports signed conflicts as
  facts. Governing computation uses only verified facts plus a caller-supplied
  UTC instant; it never reads a clock and never tie-breaks a contested view.
  """

  alias CharterAgreementProtocol.{
    Acceptance,
    ChainFacts,
    CharterRevision,
    CompactJws,
    DescriptorChain,
    Error,
    Facts,
    ForkEvidence,
    Limits,
    PartyDescriptor,
    RevisionFacts,
    TerminationFacts,
    TerminationNotice,
    Timestamp
  }

  @doc "Verify a complete caller-supplied charter artifact view."
  @spec verify(term(), term(), term(), term(), Limits.t()) ::
          {:ok, ChainFacts.t()} | {:error, Error.t()}
  def verify(revisions, acceptances, descriptors, terminations, %Limits{} = limits)
      when is_list(revisions) and is_list(acceptances) and is_list(descriptors) and
             is_list(terminations) do
    with true <- Limits.valid?(limits),
         :ok <- bounded_lists([revisions, acceptances, descriptors, terminations], limits),
         :ok <- binary_lists([revisions, acceptances, descriptors, terminations]),
         {:ok, descriptor_chains} <- verify_descriptor_chains(descriptors, limits),
         {:ok, indexed_revisions, revision_index, charter_id} <-
           verify_revisions(revisions, limits),
         {:ok, acceptance_facts} <-
           verify_acceptances(acceptances, revision_index, descriptor_chains, limits),
         :ok <- unique_acceptance_coordinates(acceptance_facts),
         {:ok, revision_facts} <- build_revision_facts(indexed_revisions, acceptance_facts),
         :ok <- accepted_supersession_targets(revision_facts),
         {:ok, termination_facts} <-
           verify_terminations(terminations, revision_index, descriptor_chains, limits) do
      build_facts(
        charter_id,
        revision_facts,
        acceptance_facts,
        descriptor_chains,
        termination_facts
      )
    else
      false -> invalid_limits()
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  def verify(_revisions, _acceptances, _descriptors, _terminations, %Limits{} = limits) do
    if Limits.valid?(limits), do: invalid_type(), else: invalid_limits()
  end

  def verify(_revisions, _acceptances, _descriptors, _terminations, _limits), do: invalid_type()

  @doc "Compute the unique governing revision in this verified view at one UTC instant."
  @spec governing_revision(term(), term()) ::
          {:ok, binary() | :contested | :none} | {:error, Error.t()}
  def governing_revision(%ChainFacts{} = facts, %DateTime{} = at) do
    with {:ok, timestamp} <- timestamp(at) do
      if terminated?(facts, timestamp), do: {:ok, :none}, else: {:ok, select(facts, timestamp)}
    end
  end

  def governing_revision(%ChainFacts{} = facts, %Timestamp{} = at) do
    if terminated?(facts, at), do: {:ok, :none}, else: {:ok, select(facts, at)}
  end

  def governing_revision(_facts, _at), do: invalid_type()

  defp bounded_lists(lists, limits) do
    if Enum.all?(lists, &(length(&1) <= limits.max_artifact_set_items)),
      do: :ok,
      else: {:error, Error.new(:limit_exceeded, ["chain", "artifacts"])}
  end

  defp binary_lists(lists) do
    if Enum.all?(List.flatten(lists), &is_binary/1), do: :ok, else: invalid_type()
  end

  defp verify_descriptor_chains([], _limits), do: chain_error()

  defp verify_descriptor_chains(compacts, limits) do
    with {:ok, decoded} <- decode_descriptors(compacts, limits),
         groups <- Enum.group_by(decoded, &descriptor_party_id/1, &elem(&1, 0)),
         true <- map_size(groups) == 2,
         {:ok, chains} <- groups |> Map.values() |> map_ok(&DescriptorChain.verify(&1, limits)) do
      {:ok, Enum.sort_by(chains, &descriptor_chain_id/1)}
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> chain_error()
    end
  end

  defp decode_descriptors(compacts, limits) do
    compacts
    |> Enum.map(fn compact ->
      case PartyDescriptor.decode(compact, limits) do
        {:ok, descriptor} -> {:ok, {compact, descriptor}}
        {:error, %Error{} = error} -> {:error, error}
      end
    end)
    |> collect_ok()
  end

  defp descriptor_party_id({_compact, descriptor}),
    do: descriptor.party_id || PartyDescriptor.digest(descriptor)

  defp descriptor_chain_id(%DescriptorChain{descriptors: descriptors}) do
    descriptors |> hd() |> Map.fetch!(:party_id)
  end

  defp verify_revisions([], _limits), do: chain_error()

  defp verify_revisions(bytes_list, limits) do
    with {:ok, revisions} <- map_ok(bytes_list, &CharterRevision.decode(&1, limits)),
         indexed <- Enum.map(revisions, &{CharterRevision.digest(&1), &1}),
         true <- unique_revision_digests?(indexed),
         revision_index <- Map.new(indexed),
         {:ok, charter_id} <- one_charter(indexed),
         :ok <- revision_links(indexed, revision_index, charter_id) do
      {:ok, indexed, revision_index, charter_id}
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> chain_error()
    end
  end

  defp unique_revision_digests?(indexed) do
    digests = Enum.map(indexed, &elem(&1, 0))
    digests == Enum.uniq(digests)
  end

  defp one_charter(indexed) do
    genesis = Enum.filter(indexed, fn {_digest, revision} -> revision.revision_number == 1 end)

    case genesis do
      [{charter_id, _root}] ->
        if one_charter?(indexed, charter_id),
          do: {:ok, charter_id},
          else: chain_error()

      _roots ->
        chain_error()
    end
  end

  defp one_charter?(indexed, charter_id) do
    Enum.all?(indexed, fn {digest, revision} ->
      (revision.charter_id || digest) == charter_id
    end)
  end

  defp revision_links(indexed, revision_index, charter_id) do
    valid? =
      Enum.all?(indexed, fn
        {_digest, %CharterRevision{revision_number: 1, prev_revision_digest: nil, supersedes: []}} ->
          true

        {_digest, %CharterRevision{} = revision} ->
          valid_predecessor?(revision, revision_index, charter_id) and
            valid_supersession_shape?(revision, revision_index, charter_id)
      end)

    if valid?, do: :ok, else: chain_error()
  end

  defp valid_predecessor?(revision, revision_index, charter_id) do
    case Map.get(revision_index, revision.prev_revision_digest) do
      %CharterRevision{} = predecessor ->
        predecessor.revision_number == revision.revision_number - 1 and
          (predecessor.charter_id || revision.prev_revision_digest) == charter_id

      nil ->
        false
    end
  end

  defp valid_supersession_shape?(revision, revision_index, charter_id) do
    Enum.all?(revision.supersedes, fn digest ->
      case Map.get(revision_index, digest) do
        %CharterRevision{} = target ->
          target.revision_number < revision.revision_number and
            (target.charter_id || digest) == charter_id

        nil ->
          false
      end
    end)
  end

  defp verify_acceptances(compacts, revision_index, descriptor_chains, limits) do
    compacts
    |> Enum.map(&verify_acceptance(&1, revision_index, descriptor_chains, limits))
    |> collect_ok()
  end

  defp verify_acceptance(compact, revision_index, descriptor_chains, limits) do
    with {:ok, revision_digest, descriptor_digest} <-
           route_claims(compact, "cap+acceptance", "revision_digest", limits),
         %CharterRevision{} = revision <- Map.get(revision_index, revision_digest),
         %DescriptorChain{} = chain <- chain_for_descriptor(descriptor_chains, descriptor_digest) do
      Acceptance.verify(compact, revision, chain, limits)
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> chain_error()
    end
  end

  defp verify_terminations(compacts, revision_index, descriptor_chains, limits) do
    compacts
    |> Enum.map(&verify_termination(&1, revision_index, descriptor_chains, limits))
    |> collect_ok()
  end

  defp verify_termination(compact, revision_index, descriptor_chains, limits) do
    with {:ok, revision_digest, descriptor_digest} <-
           route_claims(compact, "cap+termination", "governing_revision_digest", limits),
         %CharterRevision{} = revision <- Map.get(revision_index, revision_digest),
         %DescriptorChain{} = chain <- chain_for_descriptor(descriptor_chains, descriptor_digest) do
      TerminationNotice.verify(compact, revision, chain, limits)
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> chain_error()
    end
  end

  defp route_claims(compact, typ, revision_field, limits) do
    with {:ok, envelope} <- CompactJws.parse(compact, typ, limits),
         {:object, members} <- envelope.payload,
         values <- Map.new(members),
         {:string, revision_digest} <- Map.get(values, revision_field),
         {:string, descriptor_digest} <- Map.get(values, "party_descriptor_digest") do
      {:ok, revision_digest, descriptor_digest}
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> chain_error()
    end
  end

  defp chain_for_descriptor(chains, digest) do
    Enum.find(chains, fn chain ->
      Enum.any?(chain.descriptors, &(&1.descriptor_digest == digest))
    end)
  end

  defp unique_acceptance_coordinates(facts) do
    coordinates =
      Enum.map(facts, &{&1.revision_digest, &1.party_descriptor_digest, &1.party_role})

    if coordinates == Enum.uniq(coordinates), do: :ok, else: chain_error()
  end

  defp build_revision_facts(indexed_revisions, acceptance_facts) do
    indexed_revisions
    |> Enum.map(fn {digest, revision} ->
      matches = Enum.filter(acceptance_facts, &(&1.revision_digest == digest))
      status = if dual_accepted?(revision, matches), do: :accepted, else: :proposed

      Facts.build(RevisionFacts, %{
        revision: revision,
        revision_digest: digest,
        charter_id: revision.charter_id || digest,
        revision_number: revision.revision_number,
        prev_revision_digest: revision.prev_revision_digest,
        optional_extensions_retained: revision.extension_outcome.optional_retained,
        acceptance_facts: matches,
        acceptance_digests: matches |> Enum.map(& &1.acceptance_digest) |> Enum.sort(),
        acceptance_status: status
      })
    end)
    |> collect_ok()
  end

  defp dual_accepted?(revision, acceptance_facts) do
    expected =
      revision.parties
      |> Enum.map(&{&1.party_descriptor_digest, &1.role})
      |> MapSet.new()

    actual =
      acceptance_facts
      |> Enum.map(&{&1.party_descriptor_digest, &1.party_role})
      |> MapSet.new()

    actual == expected
  end

  defp accepted_supersession_targets(revision_facts) do
    accepted = accepted_revisions(revision_facts)
    accepted_digests = MapSet.new(accepted, & &1.revision_digest)

    if Enum.all?(accepted, fn facts ->
         Enum.all?(facts.revision.supersedes, &MapSet.member?(accepted_digests, &1))
       end),
       do: :ok,
       else: chain_error()
  end

  defp build_facts(
         charter_id,
         revision_facts,
         acceptance_facts,
         descriptor_chains,
         termination_facts
       ) do
    accepted = accepted_revisions(revision_facts)
    superseded = superseded_digests(accepted)
    revision_evidence = revision_fork_evidence(accepted)
    acceptance_evidence = acceptance_fork_evidence(acceptance_facts)
    descriptor_evidence = descriptor_fork_evidence(descriptor_chains)
    evidence = descriptor_evidence ++ revision_evidence ++ acceptance_evidence

    topology =
      if current_revision_fork?(accepted, superseded),
        do: :forked,
        else: :linear

    Facts.build(ChainFacts, %{
      charter_id: charter_id,
      chain_topology: topology,
      revision_facts: sort_revisions(revision_facts),
      accepted_revision_digests: accepted |> Enum.map(& &1.revision_digest) |> Enum.sort(),
      acceptance_facts: Enum.sort_by(acceptance_facts, & &1.acceptance_digest),
      descriptor_chains: descriptor_chains,
      termination_facts: Enum.sort_by(termination_facts, & &1.termination_digest),
      superseded_revision_digests: MapSet.to_list(superseded) |> Enum.sort(),
      fork_evidence: evidence
    })
  end

  defp revision_fork_evidence(accepted) do
    accepted
    |> Enum.group_by(& &1.revision_number)
    |> Enum.filter(fn {_number, facts} -> length(facts) > 1 end)
    |> Enum.map(fn {_number, facts} ->
      {:ok, evidence} =
        Facts.build(ForkEvidence, %{
          kind: :sibling_revisions,
          revision_digests: facts |> Enum.map(& &1.revision_digest) |> Enum.sort()
        })

      evidence
    end)
  end

  defp acceptance_fork_evidence(acceptance_facts) do
    acceptance_facts
    |> Enum.group_by(
      &{
        &1.charter_id,
        &1.revision_number,
        &1.party_descriptor_digest,
        &1.party_role
      }
    )
    |> Enum.filter(fn {_coordinate, facts} ->
      facts |> Enum.map(& &1.revision_digest) |> Enum.uniq() |> length() > 1
    end)
    |> Enum.map(fn {_coordinate, facts} ->
      {:ok, evidence} =
        Facts.build(ForkEvidence, %{
          kind: :equivocal_acceptances,
          revision_digests: facts |> Enum.map(& &1.revision_digest) |> Enum.uniq() |> Enum.sort(),
          acceptance_digests:
            facts |> Enum.map(& &1.acceptance_digest) |> Enum.uniq() |> Enum.sort()
        })

      evidence
    end)
  end

  defp descriptor_fork_evidence(chains) do
    chains
    |> Enum.filter(&(&1.topology == :forked))
    |> Enum.map(& &1.fork_evidence)
  end

  defp current_revision_fork?([], _superseded), do: false

  defp current_revision_fork?(accepted, superseded) do
    active = Enum.reject(accepted, &MapSet.member?(superseded, &1.revision_digest))
    not linear_candidates?(active, accepted)
  end

  defp select(facts, at) do
    accepted = accepted_revisions(facts.revision_facts)

    candidates =
      accepted
      |> Enum.reject(
        &MapSet.member?(MapSet.new(facts.superseded_revision_digests), &1.revision_digest)
      )
      |> Enum.filter(&effective?(&1.revision, at))

    case candidates do
      [] -> :none
      _facts -> select_candidates(candidates, accepted)
    end
  end

  defp select_candidates(candidates, accepted) do
    maximum = candidates |> Enum.map(& &1.revision_number) |> Enum.max()
    heads = Enum.filter(candidates, &(&1.revision_number == maximum))

    case heads do
      [head] ->
        if linear_from_head?(head, candidates, accepted),
          do: head.revision_digest,
          else: :contested

      _siblings ->
        :contested
    end
  end

  defp linear_candidates?(candidates, accepted) do
    maximum = candidates |> Enum.map(& &1.revision_number) |> Enum.max()

    case Enum.filter(candidates, &(&1.revision_number == maximum)) do
      [head] -> linear_from_head?(head, candidates, accepted)
      _siblings -> false
    end
  end

  defp linear_from_head?(head, candidates, accepted) do
    by_digest = Map.new(accepted, &{&1.revision_digest, &1})
    Enum.all?(candidates, &ancestor_or_self?(&1, head, by_digest))
  end

  defp ancestor_or_self?(candidate, head, by_digest) do
    candidate.revision_digest == head.revision_digest or
      ancestor?(candidate.revision_digest, head.prev_revision_digest, by_digest)
  end

  defp ancestor?(_candidate, nil, _by_digest), do: false
  defp ancestor?(candidate, candidate, _by_digest), do: true

  defp ancestor?(candidate, current, by_digest) do
    case Map.get(by_digest, current) do
      %RevisionFacts{prev_revision_digest: previous} -> ancestor?(candidate, previous, by_digest)
      nil -> false
    end
  end

  defp effective?(revision, at) do
    started? = Timestamp.compare(revision.effective_from, at) in [:lt, :eq]

    open? =
      is_nil(revision.effective_until) or Timestamp.compare(at, revision.effective_until) == :lt

    started? and open?
  end

  defp terminated?(facts, at) do
    Enum.any?(facts.termination_facts, fn %TerminationFacts{} = termination ->
      effective = Timestamp.compare(termination.effective_at, at) in [:lt, :eq]

      effective and
        select(facts, termination.effective_at) == termination.governing_revision_digest
    end)
  end

  defp timestamp(%DateTime{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0} = datetime) do
    datetime |> DateTime.to_iso8601() |> Timestamp.parse()
  end

  defp timestamp(_datetime), do: governing_error()

  defp accepted_revisions(revision_facts),
    do: Enum.filter(revision_facts, &(&1.acceptance_status == :accepted))

  defp superseded_digests(accepted) do
    accepted
    |> Enum.flat_map(& &1.revision.supersedes)
    |> MapSet.new()
  end

  defp sort_revisions(facts),
    do: Enum.sort_by(facts, &{&1.revision_number, &1.revision_digest})

  defp map_ok(enumerable, function),
    do: enumerable |> Enum.map(function) |> collect_ok()

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, values} -> {:cont, {:ok, [value | values]}}
      {:error, %Error{} = error}, _acc -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp chain_error, do: {:error, Error.new(:chain_invalid, ["chain"])}
  defp governing_error, do: {:error, Error.new(:governing_invalid, ["governing_revision"])}
  defp invalid_limits, do: {:error, Error.new(:invalid_limits, ["limits"])}
  defp invalid_type, do: {:error, Error.new(:invalid_type, ["chain"])}
end
