defmodule CharterAgreementProtocol.Architecture.FactsConstructionTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan
  alias CharterAgreementProtocol.{Facts, ForkEvidence}

  @floor ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth legal_validity term_satisfaction view_completeness counterparty_view wall_clock)a

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
          "%ReceiptFacts{receipt_digest: digest}",
          "alias CharterAgreementProtocol.TerminationFacts, as: Evidence",
          "alias CharterAgreementProtocol, as: CAP\n%CAP.AcceptanceFacts{}",
          "@facts_module CharterAgreementProtocol.ChainFacts\nstruct!(@facts_module, [])"
        ] do
      assert ArchitectureScan.facts_constructor_bypass_findings(source) != []
    end
  end

  test "post-construction floor suppression makes the gate red" do
    for source <- [
          "%{facts | not_verified: []}",
          "struct(facts, not_verified: [])",
          "Map.put(facts, :not_verified, [])",
          "Map.delete(facts, :not_verified)",
          "Map.merge(facts, %{not_verified: []})",
          "Map.put(map, :not_verified, Enum.uniq(@not_verified ++ additions))",
          "put_in(facts.not_verified, [])"
        ] do
      assert ArchitectureScan.facts_constructor_bypass_findings(source) != []
    end
  end

  test "the shared constructor forces the exact floor and additions cannot suppress it" do
    assert Facts.not_verified_floor() == @floor

    assert {:ok, %ForkEvidence{not_verified: not_verified}} =
             Facts.build(ForkEvidence, %{kind: :sibling_revisions}, [:signature, :tenancy])

    assert not_verified == @floor ++ [:signature]
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
