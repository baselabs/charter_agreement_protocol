defmodule CharterAgreementProtocol.JsonTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Json}

  test "decodes one complete value into the closed tagged algebra and preserves object order" do
    assert {:ok,
            {:object,
             [
               {"z", {:integer, 1}},
               {"a", {:array, [:null, {:boolean, true}, {:string, "é"}]}}
             ]}} = Json.decode(~s({"z":1,"a":[null,true,"é"]}))

    assert {:ok, {:boolean, false}} = Json.decode("false\n\t")
  end

  test "rejects duplicate members, trailing bytes, malformed syntax, and invalid encoding" do
    assert_error(Json.decode(~s({"a":1,"a":2})), :duplicate_member)
    assert_error(Json.decode("null false"), :trailing_bytes)
    assert_error(Json.decode("{"), :invalid_syntax)
    assert_error(Json.decode(<<0xFF>>), :invalid_encoding)
  end

  test "admits only integer spellings that round-trip an ECMAScript peer" do
    assert {:ok, {:integer, 9_007_199_254_740_991}} = Json.decode("9007199254740991")
    assert {:ok, {:float, value}} = Json.decode("9007199254740992")
    assert value == 9_007_199_254_740_992.0
    assert_error(Json.decode("9007199254740993"), :number_not_double_expressible)
    assert_error(Json.decode(String.duplicate("9", 400)), :number_not_double_expressible)
    assert_error(Json.decode("1e999"), :invalid_number)
  end

  test "rejects non-binary input with a value-free typed error" do
    assert {:error, %Error{code: :invalid_type, subject: ["json"], detail: nil}} =
             Json.decode(%{credential: "do-not-echo"})
  end

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code, subject: ["json"], detail: nil}} = result
  end
end
