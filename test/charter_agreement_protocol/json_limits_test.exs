defmodule CharterAgreementProtocol.JsonLimitsTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Json, Limits}

  test "byte ceiling accepts the exact bound and rejects maximum plus one" do
    assert {:ok, :null} = Json.decode("null", limits!(max_bytes: 4))
    assert_limit(Json.decode("null", limits!(max_bytes: 3)), "bytes")
  end

  test "depth ceiling is metered while OTP constructs nested containers" do
    assert {:ok, {:array, [{:integer, 0}]}} = Json.decode("[0]", limits!(max_depth: 1))
    assert_limit(Json.decode("[[0]]", limits!(max_depth: 1)), "depth")
  end

  test "object-member and array-item ceilings are independent" do
    assert {:ok, {:object, [{"a", {:integer, 1}}]}} =
             Json.decode(~S({"a":1}), limits!(max_object_members: 1))

    assert_limit(
      Json.decode(~S({"a":1,"b":2}), limits!(max_object_members: 1)),
      "object_members"
    )

    assert {:ok, {:array, [{:integer, 1}]}} =
             Json.decode("[1]", limits!(max_array_items: 1))

    assert_limit(Json.decode("[1,2]", limits!(max_array_items: 1)), "array_items")
  end

  test "string ceiling counts decoded UTF-8 bytes for values and names" do
    assert {:ok, {:string, "é"}} = Json.decode(~S("é"), limits!(max_string_bytes: 2))
    assert_limit(Json.decode(~S("é"), limits!(max_string_bytes: 1)), "string_bytes")
    assert_limit(Json.decode(~S({"é":1}), limits!(max_string_bytes: 1)), "string_bytes")
  end

  test "invalid and forged limit values fail before parsing" do
    forged = %{Limits.default() | max_depth: Limits.maximums().max_depth + 1}

    assert {:error, %Error{code: :invalid_limits, subject: ["limits"]}} =
             Json.decode("null", forged)

    assert {:error, %Error{code: :invalid_type, subject: ["limits"]}} =
             Json.decode("null", :not_limits)
  end

  defp limits!(options) do
    {:ok, limits} = Limits.new(options)
    limits
  end

  defp assert_limit(result, member) do
    assert {:error, %Error{code: :limit_exceeded, subject: ["json", ^member]}} = result
  end
end
