defmodule CharterAgreementProtocol.Canonicalization do
  @moduledoc """
  CAP never authorizes.

  RFC 8785 JSON Canonicalization Scheme over the protocol's tagged JSON algebra.

  Object names sort by unsigned UTF-16 code units, strings use the exact JSON
  control-byte escape grammar, numbers use ECMAScript shortest-round-trip
  spelling, and output is UTF-8 without inter-token whitespace. `verify/1`
  accepts received bytes only when decode→re-encode is byte-identical.
  """

  alias CharterAgreementProtocol.{Error, Json}
  alias CharterAgreementProtocol.Internal.Unicode

  @ijson_max 9_007_199_254_740_991
  @decimal_high 21
  @decimal_low -5
  @short_escapes %{?\b => "b", ?\t => "t", ?\n => "n", ?\f => "f", ?\r => "r"}

  @doc "Encode a tagged JSON value as canonical UTF-8 JSON."
  @spec encode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value) do
    case iodata(value) do
      {:ok, encoded} -> {:ok, IO.iodata_to_binary(encoded)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @doc "Verify that received JSON bytes are already canonical."
  @spec verify(term()) :: {:ok, Json.value()} | {:error, Error.t()}
  def verify(input) when is_binary(input) do
    with {:ok, value} <- Json.decode(input),
         {:ok, canonical} <- encode(value) do
      if canonical == input,
        do: {:ok, value},
        else: {:error, Error.new(:non_canonical_bytes, ["canonical_json"])}
    end
  end

  def verify(_input), do: {:error, Error.new(:invalid_type, ["canonical_json"])}

  @doc "Serialize a float using ECMAScript shortest-round-trip spelling."
  @spec number(term()) :: {:ok, binary()} | {:error, Error.t()}
  def number(float) when is_float(float) do
    cond do
      float == 0 -> {:ok, "0"}
      float < 0 -> with {:ok, encoded} <- number(-float), do: {:ok, "-" <> encoded}
      true -> {:ok, ecmascript_digits(float)}
    end
  end

  def number(_value), do: {:error, Error.new(:invalid_type, ["canonical_json"])}

  defp iodata(:null), do: {:ok, "null"}
  defp iodata({:boolean, true}), do: {:ok, "true"}
  defp iodata({:boolean, false}), do: {:ok, "false"}

  defp iodata({:integer, integer}) when is_integer(integer) do
    if abs(integer) <= @ijson_max,
      do: {:ok, Integer.to_string(integer)},
      else: {:error, Error.new(:integer_magnitude, ["canonical_json"])}
  end

  defp iodata({:float, float}) when is_float(float), do: number(float)

  defp iodata({:string, string}) when is_binary(string) do
    if Unicode.ijson_string?(string),
      do: {:ok, [?", escape(string), ?"]},
      else: {:error, Error.new(:invalid_encoding, ["canonical_json"])}
  end

  defp iodata({:array, items}) when is_list(items) do
    with {:ok, inner} <- sequence(items, []) do
      {:ok, [?[, inner, ?]]}
    end
  end

  defp iodata({:object, members}) when is_list(members) do
    with {:ok, sorted} <- sort_members(members),
         :ok <- reject_adjacent_duplicates(sorted),
         {:ok, inner} <- member_sequence(sorted, []) do
      {:ok, [?{, inner, ?}]}
    end
  end

  defp iodata(_value), do: {:error, Error.new(:invalid_type, ["canonical_json"])}

  defp sequence([], acc), do: {:ok, Enum.reverse(acc)}

  defp sequence([item | rest], acc) do
    with {:ok, encoded} <- iodata(item) do
      sequence(rest, [[maybe_comma(acc), encoded] | acc])
    end
  end

  defp sequence(_improper, _acc), do: {:error, Error.new(:invalid_type, ["canonical_json"])}

  defp member_sequence([], acc), do: {:ok, Enum.reverse(acc)}

  defp member_sequence([{name, value} | rest], acc) do
    with {:ok, key} <- iodata({:string, name}),
         {:ok, encoded} <- iodata(value) do
      member_sequence(rest, [[maybe_comma(acc), key, ?:, encoded] | acc])
    end
  end

  defp sort_members(members) do
    if proper_list?(members) and
         Enum.all?(members, fn
           {name, _value} -> is_binary(name) and String.valid?(name)
           _other -> false
         end) do
      {:ok, Enum.sort_by(members, fn {name, _value} -> sort_key(name) end)}
    else
      {:error, Error.new(:invalid_type, ["canonical_json"])}
    end
  end

  defp reject_adjacent_duplicates([{name, _} | [{name, _} | _rest]]),
    do: {:error, Error.new(:duplicate_member, ["canonical_json"])}

  defp reject_adjacent_duplicates([_member | rest]), do: reject_adjacent_duplicates(rest)
  defp reject_adjacent_duplicates([]), do: :ok

  defp maybe_comma([]), do: []
  defp maybe_comma(_acc), do: ","

  defp proper_list?([]), do: true
  defp proper_list?([_head | tail]), do: proper_list?(tail)
  defp proper_list?(_improper), do: false

  defp sort_key(name), do: :unicode.characters_to_binary(name, :utf8, {:utf16, :big})

  defp escape(<<>>), do: []
  defp escape(<<?", rest::binary>>), do: ["\\\"" | escape(rest)]
  defp escape(<<?\\, rest::binary>>), do: ["\\\\" | escape(rest)]

  defp escape(<<byte, rest::binary>>) when byte in [?\b, ?\t, ?\n, ?\f, ?\r],
    do: ["\\" <> @short_escapes[byte] | escape(rest)]

  defp escape(<<byte, rest::binary>>) when byte < 0x20,
    do: ["\\u" <> hex4(byte) | escape(rest)]

  defp escape(<<codepoint::utf8, rest::binary>>), do: [<<codepoint::utf8>> | escape(rest)]

  defp hex4(byte) do
    byte
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(4, "0")
  end

  defp ecmascript_digits(float) do
    {digits, decimal_index} = shortest(float)
    count = byte_size(digits)

    cond do
      count <= decimal_index and decimal_index <= @decimal_high ->
        digits <> String.duplicate("0", decimal_index - count)

      0 < decimal_index and decimal_index <= @decimal_high ->
        {head, tail} = String.split_at(digits, decimal_index)
        head <> "." <> tail

      @decimal_low <= decimal_index and decimal_index <= 0 ->
        "0." <> String.duplicate("0", -decimal_index) <> digits

      true ->
        exponential(digits, decimal_index)
    end
  end

  defp exponential(digits, decimal_index) do
    {first, rest} = String.split_at(digits, 1)
    mantissa = if rest == "", do: first, else: first <> "." <> rest
    exponent = decimal_index - 1
    sign = if exponent >= 0, do: "+", else: "-"
    mantissa <> "e" <> sign <> Integer.to_string(abs(exponent))
  end

  defp shortest(float) do
    {mantissa, exponent} =
      case float |> :erlang.float_to_binary([:short]) |> String.split("e") do
        [plain, power] -> {plain, String.to_integer(power)}
        [plain] -> {plain, 0}
      end

    [integer, fraction] = String.split(mantissa, ".")
    raw = integer <> fraction
    point = byte_size(integer) + exponent
    stripped = String.trim_leading(raw, "0")
    leading_zeroes = byte_size(raw) - byte_size(stripped)
    digits = String.trim_trailing(stripped, "0")
    {digits, point - leading_zeroes}
  end
end
