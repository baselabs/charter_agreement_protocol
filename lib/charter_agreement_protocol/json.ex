defmodule CharterAgreementProtocol.Json do
  @moduledoc """
  Deterministic JSON decoder producing a closed tagged value algebra.

  Object order is preserved, duplicate names and trailing non-whitespace are
  rejected, numbers must round-trip an ECMAScript double, and malformed input
  always returns a value-free typed error.
  """

  alias CharterAgreementProtocol.{Canonicalization, Error, Limits}
  alias CharterAgreementProtocol.Internal.Unicode

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
  def decode(input), do: decode(input, Limits.default())

  @doc "Decode one complete JSON value within caller-supplied ceilings."
  @spec decode(term(), term()) :: {:ok, value()} | {:error, Error.t()}
  def decode(input, %Limits{} = limits) when is_binary(input) do
    cond do
      not Limits.valid?(limits) ->
        {:error, Error.new(:invalid_limits, ["limits"])}

      byte_size(input) > limits.max_bytes ->
        limit_error("bytes")

      true ->
        decode_bounded(input, limits)
    end
  end

  def decode(_input, %Limits{} = limits) do
    if Limits.valid?(limits),
      do: {:error, Error.new(:invalid_type, ["json"])},
      else: {:error, Error.new(:invalid_limits, ["limits"])}
  end

  def decode(_input, _limits), do: {:error, Error.new(:invalid_type, ["limits"])}

  defp decode_bounded(input, limits) do
    {value, :root, rest} = :json.decode(input, :root, decoders(limits))

    if blank?(rest) do
      {:ok, sink(value)}
    else
      {:error, Error.new(:trailing_bytes, ["json"])}
    end
  rescue
    _exception -> {:error, parse_error(input)}
  catch
    :throw, {:cap_error, code} -> {:error, cap_error(code)}
    :throw, {:cap_limit, member} -> limit_error(member)
  end

  defp decoders(limits) do
    %{
      null: :null,
      integer: &{:integer, &1},
      float: &{:float, &1},
      string: fn value ->
        enforce_string_limit(value, limits)
        {:string, value}
      end,
      array_start: &container_start(:array, &1, limits),
      array_push: fn value, state -> container_push(:array, sink(value), state, limits) end,
      array_finish: fn state, parent ->
        {{:array, Enum.reverse(state.values)}, parent}
      end,
      object_start: &container_start(:object, &1, limits),
      object_push: fn {:string, key}, value, state ->
        {:string, key} = sink({:string, key})
        container_push(:object, {key, sink(value)}, state, limits)
      end,
      object_finish: fn state, parent ->
        ordered = Enum.reverse(state.values)
        reject_duplicates(ordered)
        {{:object, ordered}, parent}
      end
    }
  end

  defp container_start(kind, parent, limits) do
    depth = container_depth(parent) + 1
    if depth > limits.max_depth, do: throw({:cap_limit, "depth"})
    %{kind: kind, depth: depth, count: 0, values: []}
  end

  defp container_push(kind, value, %{kind: kind} = state, limits) do
    count = state.count + 1
    maximum = if kind == :array, do: limits.max_array_items, else: limits.max_object_members

    if count > maximum do
      member = if kind == :array, do: "array_items", else: "object_members"
      throw({:cap_limit, member})
    end

    %{state | count: count, values: [value | state.values]}
  end

  defp container_depth(:root), do: 0
  defp container_depth(%{depth: depth}), do: depth

  defp enforce_string_limit(value, limits) do
    if byte_size(value) > limits.max_string_bytes,
      do: throw({:cap_limit, "string_bytes"})
  end

  defp sink(true), do: {:boolean, true}
  defp sink(false), do: {:boolean, false}
  defp sink({:integer, lexeme}) when is_binary(lexeme), do: resolve_integer(lexeme)
  defp sink({:float, lexeme}) when is_binary(lexeme), do: resolve_float(lexeme)

  defp sink({:string, value}) do
    if Unicode.ijson_string?(value),
      do: {:string, value},
      else: throw({:cap_error, :invalid_encoding})
  end

  defp sink(value), do: value

  defp resolve_integer(lexeme) do
    integer = String.to_integer(lexeme)

    if abs(integer) <= @ijson_max do
      {:integer, integer}
    else
      case Float.parse(lexeme) do
        {float, ""} ->
          resolve_large_integer(lexeme, float)

        _error ->
          throw({:cap_error, :number_not_double_expressible})
      end
    end
  end

  defp resolve_large_integer(lexeme, float) do
    case Canonicalization.number(float) do
      {:ok, ^lexeme} -> {:float, float}
      _error -> throw({:cap_error, :number_not_double_expressible})
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
  defp cap_error(:invalid_encoding), do: Error.new(:invalid_encoding, ["json"])

  defp limit_error(member), do: {:error, Error.new(:limit_exceeded, ["json", member])}

  defp blank?(<<>>), do: true
  defp blank?(<<byte, rest::binary>>) when byte in [?\s, ?\t, ?\n, ?\r], do: blank?(rest)
  defp blank?(_rest), do: false
end
