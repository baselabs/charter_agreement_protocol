defmodule CharterAgreementProtocol.DescriptorChain do
  @moduledoc """
  CAP never authorizes.

  Complete in-view descriptor-chain verification and fork evidence.

  A fork is returned as a fact. The verifier never chooses one signed sibling
  as the winner and never claims that its input view is globally complete.
  """

  alias CharterAgreementProtocol.{
    DescriptorFacts,
    Error,
    Facts,
    ForkEvidence,
    Limits,
    PartyDescriptor
  }

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
    if Limits.valid?(limits) do
      with {:ok, verified} <- PartyDescriptor.verify_chain_view(compacts, limits) do
        {:ok, build(verified)}
      end
    else
      invalid_limits()
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

      {:ok, evidence} =
        Facts.build(ForkEvidence, %{
          kind: :sibling_descriptors,
          sibling_descriptors: siblings
        })

      %__MODULE__{
        topology: :forked,
        descriptors: sort(contested),
        fork_evidence: evidence
      }
    end
  end

  defp sort(facts), do: Enum.sort_by(facts, &{&1.descriptor_number, &1.descriptor_digest})

  defp position_linear(%DescriptorFacts{descriptor_number: number} = facts, maximum) do
    position = if number == maximum, do: :head, else: :superseded
    %{facts | descriptor_position: position}
  end

  defp chain_error, do: {:error, Error.new(:descriptor_chain_invalid, ["descriptor_chain"])}

  defp invalid_limits, do: {:error, Error.new(:invalid_limits, ["limits"])}
end
