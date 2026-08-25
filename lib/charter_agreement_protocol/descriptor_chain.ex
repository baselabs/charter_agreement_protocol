defmodule CharterAgreementProtocol.DescriptorChain do
  @moduledoc """
  Complete in-view descriptor-chain verification and fork evidence.

  A fork is returned as a fact. The verifier never chooses one signed sibling
  as the winner and never claims that its input view is globally complete.
  """

  alias CharterAgreementProtocol.{DescriptorFacts, Error, ForkEvidence, Limits, PartyDescriptor}

  @enforce_keys [:topology, :descriptors]
  defstruct [:topology, :descriptors, :fork_evidence]

  @type t :: %__MODULE__{
          topology: :linear | :forked,
          descriptors: [DescriptorFacts.t()],
          fork_evidence: nil | ForkEvidence.t()
        }

  @doc "Verify one complete descriptor view in any input order."
  @spec verify(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def verify(compacts, %Limits{} = limits) when is_list(compacts) and compacts != [] do
    with {:ok, decoded} <- decode_all(compacts, limits),
         :ok <- unique_digests(decoded),
         {:ok, genesis} <- one_genesis(decoded),
         {:ok, genesis_facts} <- PartyDescriptor.verify(genesis.compact, nil, limits),
         {:ok, verified} <- verify_reachable(decoded, [genesis_facts], limits) do
      {:ok, build(verified)}
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  def verify(compacts, %Limits{} = limits) when is_list(compacts) do
    if Limits.valid?(limits), do: chain_error(), else: invalid_limits()
  end

  def verify(_compacts, %Limits{} = limits) do
    if Limits.valid?(limits),
      do: {:error, Error.new(:invalid_type, ["descriptor_chain"])},
      else: invalid_limits()
  end

  def verify(_compacts, _limits), do: {:error, Error.new(:invalid_type, ["limits"])}

  defp decode_all(compacts, limits) do
    Enum.reduce_while(compacts, {:ok, []}, fn compact, {:ok, decoded} ->
      case PartyDescriptor.decode(compact, limits) do
        {:ok, descriptor} ->
          entry = %{
            compact: compact,
            descriptor: descriptor,
            digest: PartyDescriptor.digest(descriptor)
          }

          {:cont, {:ok, [entry | decoded]}}

        _error ->
          {:halt, chain_error()}
      end
    end)
    |> then(fn
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end)
  end

  defp unique_digests(decoded) do
    digests = Enum.map(decoded, & &1.digest)
    if digests == Enum.uniq(digests), do: :ok, else: chain_error()
  end

  defp one_genesis(decoded) do
    case Enum.filter(decoded, &(&1.descriptor.descriptor_number == 1)) do
      [genesis] -> {:ok, genesis}
      _other -> chain_error()
    end
  end

  defp verify_reachable(decoded, verified, limits) do
    known = MapSet.new(verified, & &1.descriptor_digest)

    pending =
      Enum.reject(decoded, fn entry -> MapSet.member?(known, entry.digest) end)

    ready =
      Enum.filter(pending, fn entry ->
        MapSet.member?(known, entry.descriptor.prev_descriptor_digest)
      end)

    cond do
      pending == [] ->
        {:ok, verified}

      ready == [] ->
        chain_error()

      true ->
        parents = Map.new(verified, &{&1.descriptor_digest, &1})

        with {:ok, additions} <- verify_ready(ready, parents, limits) do
          verify_reachable(decoded, verified ++ additions, limits)
        end
    end
  end

  defp verify_ready(ready, parents, limits) do
    Enum.reduce_while(ready, {:ok, []}, fn entry, {:ok, additions} ->
      predecessor = Map.fetch!(parents, entry.descriptor.prev_descriptor_digest)

      case PartyDescriptor.verify(entry.compact, predecessor, limits) do
        {:ok, facts} -> {:cont, {:ok, [facts | additions]}}
        _error -> {:halt, chain_error()}
      end
    end)
    |> then(fn
      {:ok, additions} -> {:ok, Enum.reverse(additions)}
      error -> error
    end)
  end

  defp build(verified) do
    sibling_groups =
      verified
      |> Enum.reject(&is_nil(&1.prev_descriptor_digest))
      |> Enum.group_by(& &1.prev_descriptor_digest)
      |> Map.values()
      |> Enum.filter(&(length(&1) > 1))

    if sibling_groups == [] do
      maximum = verified |> Enum.map(& &1.descriptor_number) |> Enum.max()
      positioned = Enum.map(verified, &position_linear(&1, maximum))

      %__MODULE__{topology: :linear, descriptors: sort(positioned), fork_evidence: nil}
    else
      siblings =
        sibling_groups
        |> List.flatten()
        |> Enum.map(& &1.descriptor_digest)
        |> Enum.uniq()
        |> Enum.sort()

      contested = Enum.map(verified, &%{&1 | descriptor_position: :contested})

      %__MODULE__{
        topology: :forked,
        descriptors: sort(contested),
        fork_evidence: %ForkEvidence{
          kind: :sibling_descriptors,
          sibling_descriptors: siblings
        }
      }
    end
  end

  defp sort(facts), do: Enum.sort_by(facts, &{&1.descriptor_number, &1.descriptor_digest})

  defp position_linear(%DescriptorFacts{descriptor_number: number} = facts, maximum) do
    position = if number == maximum, do: :head, else: :superseded
    %{facts | descriptor_position: position}
  end

  defp chain_error,
    do: {:error, Error.new(:descriptor_chain_invalid, ["descriptor_chain"])}

  defp invalid_limits, do: {:error, Error.new(:invalid_limits, ["limits"])}
end
