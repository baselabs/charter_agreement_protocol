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
      ArchitectureScan.identifiers_from_source("""
      def authorize_request(input) when is_map(input), do: :authorized
      defdelegate authorization_delegate(input), to: Other
      """)

    offenders =
      for {kind, name} <- identifiers,
          ArchitectureScan.authorization_token?(name),
          do: {kind, name}

    assert {:function, "authorize_request"} in offenders
    assert {:function, "authorization_delegate"} in offenders
  end
end
