defmodule CharterAgreementProtocol.Architecture.ChainRoutingShapeTest do
  use ExUnit.Case, async: true

  @source "lib/charter_agreement_protocol/chain.ex"

  test "revision routing hashes each decoded revision once into an index" do
    source = File.read!(@source)

    assert length(Regex.scan(~r/CharterRevision\.digest\(/, source)) == 1
    refute source =~ "defp revision_by_digest"
    assert source =~ "Map.get(revision_index, revision_digest)"
  end
end
