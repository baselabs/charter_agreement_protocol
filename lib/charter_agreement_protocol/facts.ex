defmodule CharterAgreementProtocol.Facts do
  @moduledoc """
  The one constructor behind every facts record, and the list of what CAP
  does not verify. Facts are non-authorizing: they describe signed evidence
  and never grant anything.

  Verification returns facts records: `CharterAgreementProtocol.ChainFacts`,
  `CharterAgreementProtocol.RevisionFacts`,
  `CharterAgreementProtocol.AcceptanceFacts`,
  `CharterAgreementProtocol.DescriptorFacts`,
  `CharterAgreementProtocol.TerminationFacts`,
  `CharterAgreementProtocol.ReceiptFacts` and
  `CharterAgreementProtocol.ForkEvidence`. Each one is built here, and each
  one carries a `not_verified` list that starts with these twelve atoms:

  `:tenancy`, `:live_policy`, `:authority`, `:effect_ownership`,
  `:execution`, `:billing`, `:evaluation_truth`, `:legal_validity`,
  `:term_satisfaction`, `:view_completeness`, `:counterparty_view` and
  `:wall_clock`.

  These name things a signature cannot prove, so your application has to
  establish them. A record may add atoms to the list (a receipt verified
  against a single revision adds `:signature`), but it never drops one. The
  [security model](security-model.md) explains each item.

  Every facts record prints as `#Name<redacted>` so that charter contents do
  not end up in logs. Read fields directly (`facts.charter_id`), or call
  `inspect(facts, structs: false)` to see everything while debugging.

  You do not need `build/3` to use CAP. It is public so the library's own
  modules share one constructor.

  `CharterAgreementProtocol.AcceptanceEquivocation` is evidence, not a facts
  record: it is not built here and has no `not_verified` list.

  ## Examples

      iex> CharterAgreementProtocol.Facts.not_verified_floor()
      [:tenancy, :live_policy, :authority, :effect_ownership, :execution, :billing,
       :evaluation_truth, :legal_validity, :term_satisfaction, :view_completeness,
       :counterparty_view, :wall_clock]
  """

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    ChainFacts,
    DescriptorFacts,
    Error,
    ForkEvidence,
    ReceiptFacts,
    RevisionFacts,
    TerminationFacts
  }

  @not_verified ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth legal_validity term_satisfaction view_completeness counterparty_view wall_clock)a
  @fact_modules [
    AcceptanceFacts,
    ChainFacts,
    DescriptorFacts,
    ForkEvidence,
    ReceiptFacts,
    RevisionFacts,
    TerminationFacts
  ]

  @doc """
  Build one facts struct of a known module.

  Sets `not_verified` to the twelve atoms plus `additions`, whatever `attrs`
  says. Returns `:invalid_type` for an unknown module, unknown fields or
  non-atom additions.
  """
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

  @doc "The twelve atoms every facts record lists in `not_verified`, in order."
  @spec not_verified_floor() :: [atom()]
  def not_verified_floor, do: @not_verified

  defp attrs_map(attrs) when is_map(attrs) and not is_struct(attrs), do: {:ok, attrs}

  defp attrs_map(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: {:ok, Map.new(attrs)}, else: invalid()
  end

  defp attrs_map(_attrs), do: invalid()
  defp invalid, do: {:error, Error.new(:invalid_type, ["facts"])}
end
