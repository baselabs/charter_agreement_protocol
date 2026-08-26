defmodule CharterAgreementProtocol.Architecture.ReleaseGateTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.Conformance.Corpus
  alias CharterAgreementProtocol.RequirementMap

  @mutation_names ~w(
    jcs-number-defeat
    padding-acceptance
    separator-collapse
    unknown-member-acceptance
    chain-signature-skip
    digest-equality-skip
    ed25519-defeat
    typ-confusion
    reason-code-uncheck
    precedence-lowest
    facts-union-suppression
    fork-topology-suppressed
    contested-tie-resolved
    acceptance-claims-mismatch-accept
    prev-binding-skip
    receipt-number-crosscheck-skip
    receipt-conflict-silenced
    equivocation-guard-removed
    stale-branch-guard-removed
    superseded-descriptor-silent-accept
    supersession-ignore
    corpus-expectation-flip
  )

  @minimum_quality_steps [
    "hex.audit",
    "deps.unlock --check-unused",
    "deps.audit",
    "format --check-formatted",
    "compile --warnings-as-errors",
    "credo --strict",
    "test --cover --seed 42",
    "conformance.verify",
    "conformance.mutations",
    "verifier.agreement",
    "dialyzer",
    "docs --warnings-as-errors",
    "release.candidate"
  ]

  test "the quality alias carries the complete release gate in order" do
    assert Mix.Project.config()[:aliases][:quality] == @minimum_quality_steps
  end

  test "every public requirement has corpus and gate evidence" do
    requirements = RequirementMap.entries()
    assert [_first | _rest] = requirements

    ids = Enum.map(requirements, &elem(&1, 0))
    assert Enum.uniq(ids) == ids

    for {id, evidence} <- requirements do
      assert id =~ ~r/\ACAP-[A-Z0-9-]+-[a-z0-9]+(?:-[a-z0-9]+)*\z/
      assert Enum.any?(evidence, &match?({:corpus, [_ | _]}, &1))
      assert Enum.any?(evidence, &match?({:gate, module} when is_atom(module), &1))
    end
  end

  test "the rendered requirements matrix ships fresh" do
    assert {:ok, contents} = File.read("spec/requirements.md")
    assert contents == RequirementMap.render_markdown()
  end

  test "mutation credit requires the exact scratch environment to be green before mutation" do
    source = File.read!("scripts/check_conformance_mutations.exs")

    assert source =~
             "scratch_green!(mutation.command, scratch)\n      mutate_once!(Path.join(scratch, mutation.path)"
  end

  test "requirement evidence resolves in both directions" do
    assert {:ok, corpus} = Corpus.load(shipped_files())
    observed = Enum.frequencies_by(corpus.cases, &{&1["surface"], &1["class"]})

    evidence = RequirementMap.entries() |> Enum.flat_map(&elem(&1, 1))

    covered_cells =
      evidence
      |> Enum.flat_map(fn
        {:corpus, cells} -> cells
        _other -> []
      end)
      |> MapSet.new()

    for {:corpus, cells} <- evidence,
        cell <- cells do
      assert [surface, class] = String.split(cell, ":", parts: 2)
      assert Map.fetch!(observed, {surface, class}) > 0
    end

    observed_cells =
      observed
      |> Map.keys()
      |> MapSet.new(fn {surface, class} -> "#{surface}:#{class}" end)

    assert MapSet.to_list(MapSet.difference(observed_cells, covered_cells)) == []

    declared_gate_modules =
      "test/architecture/*.exs"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        ~r/defmodule ([A-Za-z0-9_.]+) do/
        |> Regex.scan(File.read!(path), capture: :all_but_first)
        |> List.flatten()
      end)
      |> MapSet.new()

    for {:gate, module} <- evidence do
      assert MapSet.member?(declared_gate_modules, inspect(module))
    end

    mapped_mutations =
      evidence
      |> Enum.flat_map(fn
        {:mutation, name} -> [name]
        _other -> []
      end)

    assert mapped_mutations == @mutation_names

    source_mutations =
      RequirementMap.source_mutation_names(File.read!("scripts/check_conformance_mutations.exs"))

    assert source_mutations == @mutation_names
    assert List.last(source_mutations) == "corpus-expectation-flip"
  end

  test "OTP SHA-256 matches official NIST CAVP byte-oriented vectors" do
    vectors = [
      {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
      {Base.decode16!("D3"), "28969cdfa74a12c82f3bad960b0b000aca2ac329deea5c2328ebc6f2ba9802c1"},
      {Base.decode16!("B4190E"),
       "dff2e73091f6c05e528896c4c831b9448653dc2ff043528f6769437bc7b975c2"}
    ]

    for {message, expected} <- vectors do
      assert Base.encode16(:crypto.hash(:sha256, message), case: :lower) == expected
    end
  end

  defp shipped_files do
    "priv/conformance/**/*"
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Map.new(fn path -> {Path.relative_to(path, "priv/conformance"), File.read!(path)} end)
  end
end
