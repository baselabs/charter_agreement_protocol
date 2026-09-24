defmodule CharterAgreementProtocol.Architecture.FactsConstructionTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    DescriptorFacts,
    Facts,
    ForkEvidence,
    ReceiptFacts,
    RevisionFacts,
    TerminationFacts
  }

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

  test "every artifact facts construction site carries protocol_revision (the exposure floor)" do
    # A missed construction site would silently build a record whose revision
    # scalar is nil (defaults, not enforce_keys, by design) — this gate makes
    # the miss loud at the construction site instead of at a consumer.
    sites =
      ArchitectureScan.source_files(["lib"])
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        for module <- [
              AcceptanceFacts,
              DescriptorFacts,
              ReceiptFacts,
              RevisionFacts,
              TerminationFacts
            ],
            call = "Facts.build(" <> Atom.to_string(module) <> ",",
            String.contains?(source, call),
            not source_contains_populated_build?(source, call) do
          {path, module}
        end
      end)

    assert sites == []
  end

  defp source_contains_populated_build?(source, call) do
    case Regex.run(~r/\A.*?#{Regex.escape(call)}.*?\{\n(.*?)\n\s*\}/s, source) do
      nil ->
        # Unusual formatting: require the member within the next span of
        # this call rather than anywhere in the file (fail-closed).
        case Regex.run(~r/#{Regex.escape(call)}.{0,800}protocol_revision:/s, source) do
          nil -> false
          _ -> true
        end

      [_, body | _] ->
        String.contains?(body, "protocol_revision:")
    end
  end

  test "the exposure floor gate is red when a site drops the member" do
    source =
      "Facts.build(CharterAgreementProtocol.AcceptanceFacts, %{\n  acceptance_digest: digest\n})"

    assert source_contains_populated_build?(
             source,
             "Facts.build(CharterAgreementProtocol.AcceptanceFacts"
           ) == false
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
