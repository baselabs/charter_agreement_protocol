defmodule CharterAgreementProtocol.Quorum do
  @moduledoc "CAP never authorizes. Revision-local rules and distinct-role quorum checks."

  alias CharterAgreementProtocol.{Digest, Error}

  @type rule :: %{roles: [binary()], threshold: non_neg_integer()}
  @type replacement :: %{
          role: binary(),
          assignor_party_id: binary(),
          assignor_descriptor_digest: binary(),
          assignee_descriptor_digest: binary(),
          assent_quorum: rule()
        }

  @doc false
  @spec rule(term()) :: rule() | nil
  def rule(nil), do: nil

  def rule({:object, members}) do
    %{"roles" => {:array, roles}, "threshold" => {:integer, threshold}} = Map.new(members)
    %{roles: Enum.map(roles, &role_value/1), threshold: threshold}
  end

  defp role_value({:string, role}), do: role
  defp role_value(_value), do: nil

  @doc false
  @spec decode(map(), [struct()]) :: {:ok, rule() | nil, [replacement()]} | {:error, Error.t()}
  def decode(%{"protocol_revision" => {:integer, 8}} = values, parties) do
    roles = Enum.map(parties, & &1.role)
    acceptors = for %{role: role, participation: "acceptor"} <- parties, do: role
    acceptance = rule(values["acceptance_quorum"])
    {:object, termination} = values["termination_rules"]
    termination = rule(Map.new(termination)["quorum"])
    {:array, records} = Map.get(values, "party_replacements", {:array, []})
    replacements = Enum.map(records, &replacement/1)

    if roles == Enum.sort(roles) and valid_rule?(acceptance, acceptors, 1) and
         valid_rule?(termination, roles, 1) and
         valid_replacements?(replacements, roles, acceptance),
       do: {:ok, acceptance, replacements},
       else: {:error, Error.new(:revision_invalid, ["charter_revision"])}
  end

  def decode(_legacy, _parties), do: {:ok, nil, []}

  defp replacement({:object, members}) do
    %{
      "role" => {:string, role},
      "assignor_party_id" => {:string, owner},
      "assignor_descriptor_digest" => {:string, from},
      "assignee_descriptor_digest" => {:string, to},
      "assent_quorum" => assent
    } = Map.new(members)

    %{
      role: role,
      assignor_party_id: owner,
      assignor_descriptor_digest: from,
      assignee_descriptor_digest: to,
      assent_quorum: rule(assent)
    }
  end

  defp valid_rule?(%{roles: roles, threshold: threshold}, eligible, minimum) do
    roles == Enum.uniq(Enum.sort(roles)) and
      Enum.all?(roles, &(&1 in eligible)) and threshold >= minimum and
      threshold <= length(roles)
  end

  defp valid_replacements?(records, roles, acceptance) do
    changed = Enum.map(records, & &1.role)
    remaining = acceptance.roles -- changed
    minimum = if changed == roles, do: 0, else: 1

    changed == Enum.uniq(Enum.sort(changed)) and
      Enum.all?(records, &valid_replacement?(&1, acceptance.roles, remaining, minimum))
  end

  defp valid_replacement?(record, eligible, remaining, minimum) do
    record.role in eligible and
      valid_rule?(record.assent_quorum, remaining, minimum) and
      Enum.all?(
        [
          record.assignor_party_id,
          record.assignor_descriptor_digest,
          record.assignee_descriptor_digest
        ],
        &match?({:ok, _digest}, Digest.from_tagged(&1))
      )
  end

  @doc false
  @spec acceptance(struct()) :: rule()
  def acceptance(%{acceptance_quorum: nil, parties: parties}),
    do: %{roles: Enum.map(parties, & &1.role), threshold: length(parties)}

  def acceptance(%{acceptance_quorum: rule}), do: rule

  @doc false
  @spec termination(struct()) :: rule()
  def termination(%{termination_rules: %{quorum: nil}, parties: parties}),
    do: %{roles: Enum.map(parties, & &1.role), threshold: 1}

  def termination(%{termination_rules: %{quorum: rule}}), do: rule

  @doc false
  @spec transition?(struct(), struct(), map()) :: boolean()
  def transition?(%{protocol_revision: 8} = candidate, previous, owners) do
    old = Map.new(previous.parties, &{&1.role, &1})
    recorded = Map.new(candidate.party_replacements, &{&1.role, &1})

    length(previous.parties) == length(candidate.parties) and
      Enum.all?(candidate.parties, &binding?(&1, old, recorded, owners))
  end

  def transition?(_legacy, previous, _owners), do: previous.protocol_revision != 8

  defp binding?(party, old, recorded, owners) do
    case Map.fetch(old, party.role) do
      {:ok, predecessor} ->
        (predecessor.participation || "acceptor") == party.participation and
          binding_owner?(party, predecessor, recorded[party.role], old, owners)

      :error ->
        false
    end
  end

  defp binding_owner?(party, predecessor, record, old, owners) do
    from = predecessor.party_descriptor_digest
    to = party.party_descriptor_digest
    owner = owners[from]
    next_owner = owners[to]

    cond do
      is_nil(owner) or is_nil(next_owner) ->
        false

      owner == next_owner ->
        is_nil(record)

      is_nil(record) ->
        false

      true ->
        record.assignor_party_id == owner and record.assignor_descriptor_digest == from and
          record.assignee_descriptor_digest == to and
          Enum.all?(old, fn {_role, binding} ->
            owners[binding.party_descriptor_digest] != next_owner
          end)
    end
  end

  @doc false
  @spec accepts_binding?(struct(), struct()) :: boolean()
  def accepts_binding?(%{replacement_role: nil} = vote, revision) do
    Enum.any?(revision.parties, fn party ->
      party.role == vote.party_role and
        party.party_descriptor_digest == vote.party_descriptor_digest
    end)
  end

  def accepts_binding?(vote, revision) do
    vote.replacement_role == vote.party_role and
      Enum.any?(revision.party_replacements, fn record ->
        record.role == vote.replacement_role and
          record.assignor_descriptor_digest == vote.party_descriptor_digest
      end)
  end

  @doc false
  @spec eligible?(struct(), struct(), struct() | nil) :: boolean()
  def eligible?(vote, revision, previous) do
    vote.party_role in acceptance(revision).roles or
      (previous != nil and vote.party_role in acceptance(previous).roles) or
      revision.party_replacements != []
  end

  @doc false
  @spec evaluate(struct(), [struct()], struct() | nil) :: {boolean(), [binary()]}
  def evaluate(revision, matches, inherited) do
    {departing, arriving} = Enum.split_with(matches, &(&1.acceptance.replacement_role != nil))
    incoming = MapSet.new(arriving, & &1.party_role)
    outgoing = MapSet.new(departing, & &1.party_role)
    changed = MapSet.new(revision.party_replacements, & &1.role)
    prior_votes = MapSet.union(outgoing, MapSet.difference(incoming, changed))

    quorum =
      met?(acceptance(revision), incoming) and
        (revision.protocol_revision != 8 or inherited == nil or
           met?(acceptance(inherited), prior_votes))

    missing = missing_assent(revision, incoming, outgoing)
    {quorum, missing}
  end

  defp missing_assent(%{party_replacements: []}, _incoming, _outgoing), do: []

  defp missing_assent(revision, incoming, outgoing) do
    revision.parties
    |> Enum.map(& &1.role)
    |> Enum.reject(fn role ->
      MapSet.member?(incoming, role) and
        (Enum.all?(revision.party_replacements, &(&1.role != role)) or
           MapSet.member?(outgoing, role))
    end)
    |> Enum.sort()
  end

  @doc false
  @spec met?(rule(), Enumerable.t()) :: boolean()
  def met?(%{roles: eligible, threshold: threshold}, votes) do
    votes = MapSet.new(votes)
    Enum.count(eligible, &MapSet.member?(votes, &1)) >= threshold
  end
end
