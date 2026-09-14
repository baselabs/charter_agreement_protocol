defmodule CharterAgreementProtocol.JcsVectorsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Canonicalization, Json}

  @provenance "External RFC 8785 vectors (see test/fixtures/jcs/PROVENANCE.md)"

  test "the RFC 8785 reference vectors canonicalize to the published bytes" do
    pairs =
      "test/fixtures/jcs"
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".in.json"))

    assert length(pairs) >= 6, @provenance

    for input_name <- pairs do
      input = File.read!(Path.join("test/fixtures/jcs", input_name))
      expected_name = String.replace(input_name, ".in.json", ".out.json")
      expected = File.read!(Path.join("test/fixtures/jcs", expected_name))

      assert {:ok, value} = Json.decode(input), "#{@provenance}: #{input_name}"
      assert {:ok, canonical} = Canonicalization.encode(value), input_name

      assert canonical == expected,
             "canonical bytes diverge from the published vector: #{input_name}"
    end
  end
end
