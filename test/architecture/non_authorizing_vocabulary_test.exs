defmodule CharterAgreementProtocol.Architecture.NonAuthorizingVocabularyTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  test "no production identifier carries authorization-decision vocabulary" do
    offenders =
      for path <- ArchitectureScan.source_files(["lib"]),
          {kind, name} <- ArchitectureScan.identifiers(path),
          ArchitectureScan.authorization_token?(name),
          do: {path, kind, name}

    assert offenders == []
  end

  test "the executable-identifier walk observes planted authorization vocabulary" do
    identifiers =
      ArchitectureScan.identifiers_from_source("def authorize_request, do: :authorized")

    assert Enum.any?(identifiers, fn {_kind, name} ->
             ArchitectureScan.authorization_token?(name)
           end)
  end
end
