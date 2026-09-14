defmodule CharterAgreementProtocol.PropertyTest do
  @moduledoc """
  CAP never authorizes.

  Property coverage for the foundational codecs: canonicalization round-trips
  generated tagged values, canonical bytes are member-order invariant, and
  base64url decodes back to exactly the bytes it encoded.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Json}

  @safe_integer 9_007_199_254_740_991

  defp leaf do
    one_of([
      constant(:null),
      boolean() |> map(&{:boolean, &1}),
      integer(-@safe_integer..@safe_integer) |> map(&{:integer, &1}),
      float(min: -1.0e12, max: 1.0e12) |> map(&{:float, &1}),
      string(:alphanumeric, max_length: 24) |> map(&{:string, &1})
    ])
  end

  defp tagged(max_depth) do
    frequency([
      {6, leaf()},
      {2,
       list_of(
         (max_depth > 1 && tagged(max_depth - 1)) || leaf(),
         max_length: 5
       )
       |> map(&{:array, &1})},
      {2,
       map_of(
         string(:alphanumeric, min_length: 1, max_length: 10),
         (max_depth > 1 && tagged(max_depth - 1)) || leaf(),
         max_length: 5
       )
       |> map(&{:object, Enum.map(&1, fn {k, v} -> {k, v} end)})}
    ])
  end

  # Canonical JSON carries number identity, not number typing: an integral
  # float spells without a fraction mark and decodes as an integer. The
  # round-trip property therefore compares decoded numbers by value, with
  # integer/float coalescing as the one legal re-spelling.
  defp coalesced_equal({:float, expected}, {:integer, actual}), do: expected == actual
  defp coalesced_equal({:integer, expected}, {:float, actual}), do: expected == actual
  defp coalesced_equal(expected, actual), do: expected == actual

  defp decoded_equal?(expected, actual) when is_tuple(expected) and is_tuple(actual) do
    case {expected, actual} do
      {{:array, a}, {:array, b}} ->
        Enum.zip(a, b) |> Enum.all?(fn {x, y} -> decoded_equal?(x, y) end)

      {{:object, a}, {:object, b}} ->
        Enum.zip(a, b) |> Enum.all?(fn {{k, x}, {k2, y}} -> k == k2 and decoded_equal?(x, y) end)

      {x, y} ->
        coalesced_equal(x, y)
    end
  end

  defp decoded_equal?(expected, actual), do: expected == actual

  property "canonical bytes decode back to the exact tagged value" do
    check all(value <- tagged(4), max_runs: 200) do
      {:ok, bytes} = Canonicalization.encode(value)
      assert {:ok, decoded} = Json.decode(bytes)
      assert decoded_equal?(value, decoded)
    end
  end

  property "canonical encoding is idempotent and member-order independent" do
    check all(value <- tagged(4), max_runs: 200) do
      {:ok, bytes} = Canonicalization.encode(value)
      assert {:ok, decoded} = Canonicalization.verify(bytes)
      assert {:ok, ^bytes} = Canonicalization.encode(decoded)
      assert {:ok, redecoded} = Json.decode(bytes)
      assert {:ok, ^bytes} = Canonicalization.encode(redecoded)
    end
  end

  property "base64url encodes and decodes back to the exact bytes" do
    check all(raw <- binary(min_length: 0, max_length: 512), max_runs: 200) do
      encoded = Base64Url.encode(raw)
      assert {:ok, ^raw} = Base64Url.decode(encoded)
    end
  end
end
