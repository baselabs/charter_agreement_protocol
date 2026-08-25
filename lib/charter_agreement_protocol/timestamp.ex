defmodule CharterAgreementProtocol.Timestamp do
  @moduledoc """
  Pure RFC 3339 UTC timestamp parsing and comparison.

  Parsing never reads a clock. The protocol narrows RFC 3339 to uppercase `T`
  and a `Z` offset while retaining fractional seconds and leap-second syntax.
  `ordering_ticks` is an internal total-order coordinate that preserves the
  leap-second slot; it is not an elapsed-seconds value.
  """

  alias CharterAgreementProtocol.Error

  @enforce_keys [:ordering_ticks, :fraction]
  defstruct [:ordering_ticks, :fraction]

  @type t :: %__MODULE__{ordering_ticks: non_neg_integer(), fraction: binary()}

  @pattern ~r/\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?Z\z/

  @doc "Parse one exact UTC RFC 3339 instant."
  @spec parse(term()) :: {:ok, t()} | {:error, Error.t()}
  def parse(value) when is_binary(value) do
    case Regex.run(@pattern, value, capture: :all_but_first) do
      [year, month, day, hour, minute, second] ->
        build(year, month, day, hour, minute, second, "")

      [year, month, day, hour, minute, second, fraction] ->
        build(year, month, day, hour, minute, second, fraction)

      _no_match ->
        invalid()
    end
  end

  def parse(_value), do: {:error, Error.new(:invalid_type, ["timestamp"])}

  @doc "Compare two parsed instants."
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    case order(left.ordering_ticks, right.ordering_ticks) do
      :eq -> compare_fraction(left.fraction, right.fraction)
      ordering -> ordering
    end
  end

  defp build(year, month, day, hour, minute, second, fraction) do
    values = Enum.map([year, month, day, hour, minute, second], &String.to_integer/1)
    [year, month, day, hour, minute, second] = values

    with {:ok, date} <- Date.new(year, month, day),
         true <- hour in 0..23 and minute in 0..59,
         true <- valid_second?(month, day, hour, minute, second) do
      base_second = min(second, 59)
      nominal = Date.to_gregorian_days(date) * 86_400 + hour * 3_600 + minute * 60 + base_second
      leap_tick = if second == 60, do: 1, else: 0

      {:ok,
       %__MODULE__{
         ordering_ticks: nominal * 2 + leap_tick,
         fraction: String.trim_trailing(fraction, "0")
       }}
    else
      _failure -> invalid()
    end
  end

  defp valid_second?(_month, _day, _hour, _minute, second) when second in 0..59, do: true

  defp valid_second?(month, day, 23, 59, 60),
    do: {month, day} in [{6, 30}, {12, 31}]

  defp valid_second?(_month, _day, _hour, _minute, _second), do: false

  defp compare_fraction(left, right) do
    width = max(byte_size(left), byte_size(right))
    order(String.pad_trailing(left, width, "0"), String.pad_trailing(right, width, "0"))
  end

  defp order(left, right) when left < right, do: :lt
  defp order(left, right) when left > right, do: :gt
  defp order(_left, _right), do: :eq

  defp invalid, do: {:error, Error.new(:timestamp_invalid, ["timestamp"])}
end
