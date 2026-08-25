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

  test "guarded, predicate, plural, and CamelCase verdict forms are observable" do
    sources = [
      "def compliant?(input) when is_map(input), do: true",
      "def within_limits!, do: true",
      "defdelegate permitted(input), to: Other",
      "def satisfied?, do: true",
      "def in_band?, do: true",
      "defmodule TermsSatisfiedView do end"
    ]

    for source <- sources do
      identifiers = ArchitectureScan.identifiers_from_source(source)

      assert Enum.any?(identifiers, fn {_kind, name} ->
               ArchitectureScan.term_evaluation_token?(name)
             end)
    end
  end
end
