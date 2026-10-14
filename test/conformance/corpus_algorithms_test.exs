defmodule CharterAgreementProtocol.Conformance.CorpusAlgorithmsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ConformanceTest.CorpusAlgorithms

  defp segment(text), do: Base.url_encode64(text, padding: false)

  test "cases split on the algorithm their compact headers name" do
    ml_dsa = %{
      "id" => "ml",
      "input" => %{"compact" => segment(~s({"alg":"ML-DSA-65"})) <> ".e30.AA"}
    }

    ed25519 = %{
      "id" => "ed",
      "input" => %{"compact" => segment(~s({"alg":"Ed25519"})) <> ".e30.AA"}
    }

    array_header = %{"id" => "array", "input" => %{"compact" => segment("[1]") <> ".e30.AA"}}
    cases = [ml_dsa, ed25519, array_header]

    assert Enum.map(CorpusAlgorithms.select(cases, :ml_dsa), & &1["id"]) == ["ml"]
    assert Enum.map(CorpusAlgorithms.select(cases, :classic), & &1["id"]) == ["ed", "array"]
  end
end
