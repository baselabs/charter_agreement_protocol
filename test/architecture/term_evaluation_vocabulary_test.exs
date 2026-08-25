defmodule CharterAgreementProtocol.Architecture.TermEvaluationVocabularyTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  test "core identifiers carry no term-evaluation verdict vocabulary" do
    offenders =
      for path <- ArchitectureScan.source_files(["lib"]),
          {kind, name} <- ArchitectureScan.identifiers(path),
          ArchitectureScan.term_evaluation_token?(name),
          do: {path, kind, name}

    assert offenders == []
  end

  test "every forbidden verdict family is observable by the identifier gate" do
    for token <- ~w(compliant within_limit permitted satisfied in_band) do
      identifiers =
        ArchitectureScan.identifiers_from_source("def #{token}, do: :#{token}")

      assert Enum.any?(identifiers, fn {_kind, name} ->
               ArchitectureScan.term_evaluation_token?(name)
             end)
    end
  end
end
