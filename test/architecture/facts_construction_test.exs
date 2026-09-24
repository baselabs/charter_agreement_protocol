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

  test "every artifact facts construction site carries its revision (and, where signed, alg) scalars" do
    # A missed construction site would silently build a record whose revision
    # scalar is nil (defaults, not enforce_keys, by design) — this gate makes
    # the miss loud at the construction site instead of at a consumer. Every
    # Facts.build block per module is inspected (not just the first), the
    # unsigned revision record is exempt from the alg floor (no envelope), and
    # the four signed-artifact records must populate both scalars.
    signed = [AcceptanceFacts, DescriptorFacts, ReceiptFacts, TerminationFacts]

    sites =
      ArchitectureScan.source_files(["lib"])
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        for module <- [RevisionFacts | signed],
            call = "Facts.build(" <> Atom.to_string(module) <> ",",
            block <- build_blocks(source, call),
            missing = missing_members(block, module in signed),
            missing != [] do
          {path, module, missing}
        end
      end)

    assert sites == []
  end

  # Every Facts.build block for this module in the source, as raw text.
  defp build_blocks(source, call) do
    ~r/#{Regex.escape(call)}.*?\{\n(.*?)\n\s*\}/s
    |> Regex.scan(source, capture: :all_but_first)
    |> List.wrap()
    |> Enum.map(&List.first/1)
  end

  # Which exposure members a build block fails to populate. The unsigned
  # revision record owes only protocol_revision; the signed records owe both.
  defp missing_members(block, signed?) do
    owed = if signed?, do: ["protocol_revision:", "alg:"], else: ["protocol_revision:"]

    Enum.reject(owed, &String.contains?(block, &1))
  end

  test "the exposure floor gate is red when a site drops a member" do
    source =
      "Facts.build(CharterAgreementProtocol.AcceptanceFacts, %{\n  acceptance_digest: digest\n})"

    assert build_blocks(source, "Facts.build(CharterAgreementProtocol.AcceptanceFacts,") == [
             "  acceptance_digest: digest"
           ]

    assert missing_members("  acceptance_digest: digest", true) == ["protocol_revision:", "alg:"]

    unsigned =
      "Facts.build(CharterAgreementProtocol.RevisionFacts, %{\n  revision_digest: digest\n})"

    assert missing_members("  revision_digest: digest", false) == ["protocol_revision:"]
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
