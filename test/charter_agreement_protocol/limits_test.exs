defmodule CharterAgreementProtocol.LimitsTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Limits}

  test "defaults are closed, valid, and below their compiled maximums" do
    limits = Limits.default()
    maximums = Limits.maximums()

    assert Limits.valid?(limits)

    for field <- Limits.fields() do
      assert Map.fetch!(limits, field) <= Map.fetch!(maximums, field)
    end
  end

  test "callers may narrow or widen within the compiled maximums" do
    assert {:ok, default} = Limits.new()
    assert default == Limits.default()

    assert {:ok, %Limits{max_depth: 1, max_array_items: 2}} =
             Limits.new(max_depth: 1, max_array_items: 2)

    maximum_options = Limits.maximums() |> Map.take(Limits.fields()) |> Map.to_list()
    assert {:ok, maximums} = Limits.new(maximum_options)
    assert maximums == Limits.maximums()
  end

  test "unknown, duplicate, negative, non-integer, and above-maximum input fails closed" do
    for options <- [
          :not_a_keyword,
          [unknown: 1],
          [max_depth: 1, max_depth: 2],
          [max_depth: -1],
          [max_depth: 1.5],
          [max_depth: Limits.maximums().max_depth + 1]
        ] do
      assert {:error, %Error{code: :invalid_limits, subject: ["limits"]}} =
               Limits.new(options)
    end

    refute Limits.valid?(%{max_depth: 1})
  end
end
