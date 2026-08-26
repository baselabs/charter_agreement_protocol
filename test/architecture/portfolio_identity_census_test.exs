defmodule CharterAgreementProtocol.Architecture.PortfolioIdentityCensusTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  @separator_prefixes ["charter-agreement-protocol/", "agent-blueprint-protocol/", "BAP"]
  @protected_type ~r/^[a-z][a-z0-9.-]*\+[a-z0-9+.-]+$/

  test "CAP separators are complete and disjoint from exact portfolio dependencies" do
    cap = strings("lib") |> portfolio_separators()
    abp = strings("deps/agent_blueprint_protocol/lib") |> portfolio_separators()
    bap = strings("deps/bounded_authority_protocol/lib") |> portfolio_separators()

    assert cap ==
             MapSet.new(~w(
               charter-agreement-protocol/acceptance-content
               charter-agreement-protocol/charter-revision-content
               charter-agreement-protocol/conformance-report
               charter-agreement-protocol/corpus-index
               charter-agreement-protocol/extension-registry
               charter-agreement-protocol/extension-schema
               charter-agreement-protocol/legal-text
               charter-agreement-protocol/party-descriptor-content
               charter-agreement-protocol/receipt-content
               charter-agreement-protocol/signature
               charter-agreement-protocol/specification
               charter-agreement-protocol/termination-content
             ))

    assert abp ==
             MapSet.new(~w(
               agent-blueprint-protocol/blueprint-content
               agent-blueprint-protocol/conformance-report
               agent-blueprint-protocol/corpus-index
               agent-blueprint-protocol/deployment-content
               agent-blueprint-protocol/extension-registry
               agent-blueprint-protocol/extension-schema
               agent-blueprint-protocol/federation-envelope
               agent-blueprint-protocol/signature
             ))

    assert bap ==
             MapSet.new([
               "BAP1-ARCHIVE\0EXPORT\0",
               "BAP1-CHAIN\0",
               "BAP1-REQUEST"
             ])

    assert pairwise_disjoint?([cap, abp, bap])
  end

  test "CAP protected types are complete and disjoint from exact portfolio dependencies" do
    cap = strings("lib") |> matching(@protected_type)

    portfolio =
      ["deps/agent_blueprint_protocol/lib", "deps/bounded_authority_protocol/lib"]
      |> Enum.flat_map(&strings/1)
      |> matching(@protected_type)

    assert cap == MapSet.new(~w(cap+acceptance cap+party cap+receipt cap+termination))
    assert MapSet.new(~w(ba+cap ba+chain-anchor ba+key-transition dpop+jwt)) == portfolio
    assert MapSet.disjoint?(cap, portfolio)
  end

  defp strings(root) do
    [root]
    |> ArchitectureScan.source_files()
    |> ArchitectureScan.string_literals()
  end

  defp portfolio_separators(strings) do
    strings
    |> Enum.filter(fn string ->
      Enum.any?(@separator_prefixes, &String.starts_with?(string, &1))
    end)
    |> MapSet.new()
  end

  defp matching(strings, expression),
    do: strings |> Enum.filter(&Regex.match?(expression, &1)) |> MapSet.new()

  defp pairwise_disjoint?([first, second, third]) do
    MapSet.disjoint?(first, second) and MapSet.disjoint?(first, third) and
      MapSet.disjoint?(second, third)
  end
end
