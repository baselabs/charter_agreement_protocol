defmodule CharterAgreementProtocol.Json do
  @moduledoc """
  Deterministic JSON decoder producing a closed tagged value algebra.

  Object order is preserved, duplicate names and trailing non-whitespace are
  rejected, numbers must round-trip an ECMAScript double, and malformed input
  always returns a value-free typed error.
  """

  alias CharterAgreementProtocol.{Canonicalization, Error}

  @ijson_max 9_007_199_254_740_991

  @type value ::
          :null
          | {:boolean, boolean()}
          | {:integer, integer()}
          | {:float, float()}
          | {:string, binary()}
          | {:array, [value()]}
          | {:object, [{binary(), value()}]}

  @doc "Decode one complete JSON value."
  @spec decode(term()) :: {:ok, value()} | {:error, Error.t()}
  def decode(input) when is_binary(input) do
    {value, :root, rest} = :json.decode(input, :root, decoders())

    if blank?(rest) do
      {:ok, sink(value)}
    else
      {:error, Error.new(:trailing_bytes, ["json"])}
    end
  rescue
    _exception -> {:error, parse_error(input)}
  catch
    :throw, {:cap_error, code} -> {:error, cap_error(code)}
  end

  def decode(_input), do: {:error, Error.new(:invalid_type, ["json"])}

  defp decoders do
    %{
      null: :null,
      integer: &{:integer, &1},
      float: &{:float, &1},
      string: &{:string, &1},
      array_start: fn _parent -> [] end,
      array_push: fn value, items -> [sink(value) | items] end,
      array_finish: fn items, parent -> {{:array, Enum.reverse(items)}, parent} end,
      object_start: fn _parent -> [] end,
      object_push: fn {:string, key}, value, members -> [{key, sink(value)} | members] end,
      object_finish: fn members, parent ->
        ordered = Enum.reverse(members)
        reject_duplicates(ordered)
        {{:object, ordered}, parent}
      end
    }
  end

  defp sink(true), do: {:boolean, true}
  defp sink(false), do: {:boolean, false}
  defp sink({:integer, lexeme}) when is_binary(lexeme), do: resolve_integer(lexeme)
  defp sink({:float, lexeme}) when is_binary(lexeme), do: resolve_float(lexeme)
  defp sink(value), do: value

  defp resolve_integer(lexeme) do
    integer = String.to_integer(lexeme)

    if abs(integer) <= @ijson_max do
      {:integer, integer}
    else
      {float, ""} = Float.parse(lexeme)

      case Canonicalization.number(float) do
        {:ok, ^lexeme} -> {:float, float}
        _error -> throw({:cap_error, :number_not_double_expressible})
      end
    end
  end

  defp resolve_float(lexeme) do
    case Float.parse(lexeme) do
      {float, ""} -> {:float, float}
      _error -> throw({:cap_error, :invalid_number})
    end
  end

  defp reject_duplicates(members) do
    keys = Enum.map(members, &elem(&1, 0))
    if keys != Enum.uniq(keys), do: throw({:cap_error, :duplicate_member})
  end

  defp parse_error(input) do
    if String.valid?(input),
      do: Error.new(:invalid_syntax, ["json"]),
      else: Error.new(:invalid_encoding, ["json"])
  end

  defp cap_error(:invalid_number), do: Error.new(:invalid_number, ["json"])

  defp cap_error(:number_not_double_expressible),
    do: Error.new(:number_not_double_expressible, ["json"])

  defp cap_error(:duplicate_member), do: Error.new(:duplicate_member, ["json"])

  defp blank?(<<>>), do: true
  defp blank?(<<byte, rest::binary>>) when byte in [?\s, ?\t, ?\n, ?\r], do: blank?(rest)
  defp blank?(_rest), do: false
end
