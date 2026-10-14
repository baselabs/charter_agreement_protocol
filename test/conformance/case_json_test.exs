defmodule CharterAgreementProtocol.Conformance.CaseJsonTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Canonicalization, Error, Json}
  alias CharterAgreementProtocol.Conformance.Corpus
  alias CharterAgreementProtocol.ConformanceTest.Builder
  alias CharterAgreementProtocol.Internal.CaseJson

  test "case encoding preserves nested whole floats and canonical member ordering" do
    plain = %{"z" => [2.0, 1, 1.5, 1.0e21], "a" => %{"min" => 1.0}}
    assert {:ok, value} = Canonicalization.from_plain(plain)
    assert {:ok, bytes} = CaseJson.encode(value)
    assert bytes == ~s({"a":{"min":1.0},"z":[2.0,1,1.5,1e+21]})
    assert {:ok, decoded} = Json.decode(bytes)
    assert {:ok, ^bytes} = CaseJson.encode(decoded)
    assert {:ok, ~s({"a":{"min":1},"z":[2,1,1.5,1e+21]})} = Canonicalization.encode(value)
    assert {:error, %Error{code: :invalid_type}} = CaseJson.encode(:invalid)
  end

  test "the corpus loader retains float tokens in case inputs" do
    files =
      Builder.build()
      |> Builder.update_cases(fn [one | rest] ->
        [put_in(one, ["input", "float_value"], 1.0) | rest]
      end)

    assert {:ok, corpus} = Corpus.load(files)
    assert is_float(hd(corpus.cases)["input"]["float_value"])
  end
end
