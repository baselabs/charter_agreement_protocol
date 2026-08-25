defmodule CharterAgreementProtocol.Facts do
  @moduledoc "Shared constructor for CAP's redacted, non-authorizing facts records."

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    ChainFacts,
    DescriptorFacts,
    Error,
    ForkEvidence,
    RevisionFacts,
    TerminationFacts
  }

  @not_verified ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth legal_validity term_satisfaction view_completeness counterparty_view wall_clock)a
  @fact_modules [
    AcceptanceFacts,
    ChainFacts,
    DescriptorFacts,
    ForkEvidence,
    RevisionFacts,
    TerminationFacts
  ]

  @doc "Build one known facts struct, forcing the twelve-atom floor and unioning additions."
  @spec build(module(), map() | keyword(), [atom()]) :: {:ok, struct()} | {:error, Error.t()}
  def build(module, attrs, additions \\ [])

  def build(module, attrs, additions)
      when module in @fact_modules and is_list(additions) do
    with {:ok, map} <- attrs_map(attrs),
         true <- Enum.all?(additions, &is_atom/1) do
      values = Map.put(map, :not_verified, Enum.uniq(@not_verified ++ additions))

      try do
        {:ok, struct!(module, values)}
      rescue
        _error -> invalid()
      end
    else
      _failure -> invalid()
    end
  end

  def build(_module, _attrs, _additions), do: invalid()

  @doc "The fixed host-owned floor, exposed for architecture and property gates."
  @spec not_verified_floor() :: [atom()]
  def not_verified_floor, do: @not_verified

  defp attrs_map(attrs) when is_map(attrs) and not is_struct(attrs), do: {:ok, attrs}

  defp attrs_map(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: {:ok, Map.new(attrs)}, else: invalid()
  end

  defp attrs_map(_attrs), do: invalid()
  defp invalid, do: {:error, Error.new(:invalid_type, ["facts"])}
end
