defmodule CharterAgreementProtocol.Architecture.ErrorCodeReferenceTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.Error

  @reference "docs/guides/error-codes.md"
  @row ~r/^\| `:([a-z0-9_]+)` \| (corpus-exercised|test-exercised|declared) \| /

  test "the error-code reference tabulates exactly the closed code list" do
    codes = table() |> Enum.map(&elem(&1, 0))
    assert codes == Enum.map(Error.codes(), &Atom.to_string/1) |> Enum.sort()
  end

  test "every tabulated coverage class matches the live evidence" do
    corpus = corpus_expected_codes()

    for {code, declared_class} <- table() do
      live_class =
        cond do
          code in corpus -> "corpus-exercised"
          test_referenced?(code) -> "test-exercised"
          true -> "declared"
        end

      assert {code, declared_class} == {code, live_class}
    end
  end

  defp table do
    assert {:ok, contents} = File.read(@reference)

    for line <- String.split(contents, "\n"),
        captures = Regex.run(@row, line),
        [_, code, coverage] <- [captures] do
      {code, coverage}
    end
  end

  defp corpus_expected_codes do
    "priv/conformance/cases/*.json"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      %{"cases" => cases} = :json.decode(File.read!(path))
      cases |> Enum.map(& &1["expect"]["error_code"]) |> Enum.reject(&is_nil/1)
    end)
    |> MapSet.new()
  end

  defp test_referenced?(code) do
    {output, _status} = System.cmd("grep", ["-rlw", code, "test/"])
    output != ""
  end
end
