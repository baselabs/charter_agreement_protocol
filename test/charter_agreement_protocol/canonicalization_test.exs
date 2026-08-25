defmodule CharterAgreementProtocol.CanonicalizationTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Canonicalization, Error}

  test "serializes RFC number edge cases with ECMAScript spelling" do
    for {bits, expected} <- [
          {0x0000000000000000, "0"},
          {0x8000000000000000, "0"},
          {0x0000000000000001, "5e-324"},
          {0x8000000000000001, "-5e-324"},
          {0x3EB0C6F7A0B5ED8C, "9.999999999999997e-7"},
          {0x3EB0C6F7A0B5ED8D, "0.000001"},
          {0x41B3DE4355555555, "333333333.3333333"},
          {0x43143FF3C1CB0959, "1424953923781206.2"},
          {0x444B1AE4D6E2EF50, "1e+21"}
        ] do
      <<value::float-64>> = <<bits::unsigned-64>>
      assert Canonicalization.encode({:float, value}) == {:ok, expected}
    end
  end

  test "uses the exact control-byte grammar and preserves Unicode without normalization" do
    value = {:string, <<0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x0F, ?", ?\\, ?/, "é"::utf8>>}

    assert Canonicalization.encode(value) == {:ok, ~s("\\b\\t\\n\\f\\r\\u000f\\"\\\\/é")}
    assert Canonicalization.encode({:string, "e\u0301"}) == {:ok, ~s("é")}
  end

  test "encodes every scalar in the tagged algebra" do
    assert Canonicalization.encode(:null) == {:ok, "null"}
    assert Canonicalization.encode({:boolean, true}) == {:ok, "true"}
    assert Canonicalization.encode({:boolean, false}) == {:ok, "false"}
    assert Canonicalization.encode({:integer, -17}) == {:ok, "-17"}
  end

  test "sorts object names recursively by unsigned UTF-16 units and preserves array order" do
    value =
      {:array,
       [
         {:object,
          [
            {"\uFB33", :null},
            {"😀", :null},
            {"€", :null},
            {"1", :null},
            {"\r", :null},
            {"ö", :null},
            {"\u0080", :null}
          ]},
         {:object, [{"z", {:integer, 1}}, {"a", {:integer, 2}}]}
       ]}

    assert {:ok, encoded} = Canonicalization.encode(value)

    assert encoded ==
             "[{\"\\r\":null,\"1\":null,\"\u0080\":null,\"ö\":null,\"€\":null,\"😀\":null,\"דּ\":null},{\"a\":2,\"z\":1}]"
  end

  test "verifies canonical interchange bytes before returning decoded values" do
    assert Canonicalization.verify(~s({"a":1,"z":2})) ==
             {:ok, {:object, [{"a", {:integer, 1}}, {"z", {:integer, 2}}]}}

    for noncanonical <- [~s({ "a":1}), ~s({"z":2,"a":1}), ~s({"a":1.0}), ~S({"a":"\u0062"})] do
      assert_error(Canonicalization.verify(noncanonical), :non_canonical_bytes)
    end
  end

  test "encode fails closed for invalid constructed values" do
    assert_error(Canonicalization.encode({:integer, 9_007_199_254_740_992}), :integer_magnitude)
    assert_error(Canonicalization.encode({:string, <<0xFF>>}), :invalid_encoding)

    assert_error(
      Canonicalization.encode({:object, [{"a", :null}, {"a", :null}]}),
      :duplicate_member
    )

    assert_error(Canonicalization.encode({:array, [:null | :improper]}), :invalid_type)
    assert_error(Canonicalization.encode({:object, [:not_a_member]}), :invalid_type)
    assert_error(Canonicalization.encode({:unsupported, "secret"}), :invalid_type)
    assert_error(Canonicalization.number(1), :invalid_type)
    assert_error(Canonicalization.verify(:not_bytes), :invalid_type)
  end

  defp assert_error(result, code) do
    assert {:error, %Error{code: ^code, subject: ["canonical_json"], detail: nil}} = result
  end
end
