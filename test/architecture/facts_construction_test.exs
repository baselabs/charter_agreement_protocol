defmodule CharterAgreementProtocol.Architecture.FactsConstructionTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  test "all production facts construction routes through the shared constructor" do
    findings =
      ArchitectureScan.source_files(["lib"])
      |> Enum.flat_map(fn path ->
        ArchitectureScan.facts_constructor_bypass_findings(path)
        |> Enum.map(&{path, &1})
      end)

    assert findings == []
  end

  test "literal, dynamic, applied, and renamed facts constructors make the gate red" do
    for source <- [
          "%AcceptanceFacts{acceptance_digest: digest}",
          "struct(ChainFacts, charter_id: digest)",
          "Kernel.struct!(DescriptorFacts, descriptor_digest: digest)",
          "apply(ForkEvidence, :__struct__, [[kind: :sibling_revisions]])",
          "alias CharterAgreementProtocol.TerminationFacts, as: Evidence"
        ] do
      assert ArchitectureScan.facts_constructor_bypass_findings(source) != []
    end
  end

  test "read-only facts patterns remain allowed" do
    for source <- [
          "def digest(%RevisionFacts{revision_digest: digest}), do: digest",
          "case facts do %ChainFacts{} = facts -> facts end",
          "with %TerminationFacts{} <- facts, do: :ok"
        ] do
      assert ArchitectureScan.facts_constructor_bypass_findings(source) == []
    end
  end
end
