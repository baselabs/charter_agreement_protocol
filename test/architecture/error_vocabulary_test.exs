defmodule CharterAgreementProtocol.Architecture.ErrorVocabularyTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{ArchitectureScan, Error}

  test "every production error construction uses a declared literal code" do
    calls =
      Enum.flat_map(ArchitectureScan.source_files(["lib"]), &ArchitectureScan.error_code_calls/1)

    dynamic = Enum.reject(calls, &is_atom/1)
    undeclared = for code <- calls, is_atom(code), not Error.declared?(code), do: code

    assert dynamic == []
    assert undeclared == []
  end

  test "every declared code has a production emission site" do
    emitted =
      ArchitectureScan.source_files(["lib"])
      |> Enum.flat_map(&ArchitectureScan.error_code_calls/1)
      |> Enum.filter(&is_atom/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert emitted == Enum.sort(Error.codes())
  end
end
