Code.require_file("../../scripts/release_compatibility.exs", __DIR__)
Code.require_file("../../scripts/reverse_corpus.exs", __DIR__)
Code.require_file("../../scripts/seeded_mutation.exs", __DIR__)

defmodule CharterAgreementProtocol.Architecture.ReleaseGateTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.Conformance.Corpus

  alias CharterAgreementProtocol.{
    ReleaseCompatibility,
    ReleaseIdentity,
    RequirementMap,
    ReverseCorpus,
    SeededMutation
  }

  @mutation_names ~w(
    next-key-opening-skip
    next-key-prefix-dropped
    next-key-algorithm-omitted
    next-key-id-included
    next-key-retired-included
    next-key-downgrade-accepted
    publication-link-skip
    publication-selects-fork
    publication-history-profile-skip
    publication-effective-order-skip
    json-syntax-before-container-limits
    chain-empty-before-set-checks
    runner-null-axis-default
    case-float-token-collapse
    ed25519-native-power-skip
    runner-option-member-code-revert
    receipt-caller-limits-skip
    retained-revision-fields-skip
    signing-termination-profile-skip
    ed25519-r-check-skip
    ed25519-canonical-y-skip
    termination-context-code-revert
    termination-lineage-code-revert
    acceptance-lineage-code-revert
    provider-runtime-query-rescue-skip
    provider-known-answer-rescue-skip
    provider-library-query-rescue-skip
    signing-limits-order-skip
    signing-profile-order-skip
    signing-context-type-skip
    signing-build-default-limits
    signing-key-shape-skip
    signing-strict-point-skip
    signing-snapshot-match-skip
    signing-receipt-first-key-only
    signing-runtime-support-invert
    signing-refusal-skip
    signing-unheld-code-collapse
    signing-termination-code-collapse
    signing-finish-default-limits
    signing-finish-verify-skip
    signing-finish-profile-skip
    signing-set-profile-skip
    signing-set-profile-narrow
    signing-set-limits-skip
    signing-shared-prepare-skip
    signing-retained-envelope-guard-skip
    signing-retained-list-guard-skip
    signing-retained-lineage-guard-skip
    signing-runtime-cache-skip
    signing-retained-shape-skip
    jcs-number-defeat
    padding-acceptance
    separator-collapse
    unknown-member-acceptance
    chain-signature-skip
    digest-equality-skip
    ed25519-defeat
    ed25519-list-only-admission
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
    alg-binding-defeat
    mldsa-binding-defeat
    mldsa-key-grammar-gate-defeat
    profile-gate-defeat
    profile-revision-gate-defeat
    termination-close-ignored
    revision-canonical-bytes-skip
    artifact-set-bytes-ceiling-skip
    distinct-descriptors-skip
    party-histories-skip
    two-party-history-count-relaxed
    context-descriptor-profile-skip
    context-revision-profile-skip
    context-order-swapped
    termination-descriptor-profile-skip
    chain-receipt-context-profile-skip
    chain-receipt-admission-skip
    predecessor-profile-code-swallowed
    termination-order-swapped
    descriptor-admission-before-key-skip
    revision-only-receipt-profile-skip
  )

  @minimum_quality_steps [
    "hex.audit",
    "deps.unlock --check-unused",
    "deps.audit",
    "currency.check",
    "format --check-formatted",
    "compile --warnings-as-errors",
    "credo --strict",
    "verifier.source",
    "test --cover --seed 42",
    "conformance.verify",
    "historical.check",
    "historical.reverse",
    "conformance.mutations",
    "verifier.agreement",
    "differential.check",
    "dialyzer",
    "docs --warnings-as-errors",
    "release.candidate"
  ]

  test "the quality alias carries the complete release gate in order" do
    assert Mix.Project.config()[:aliases][:quality] == @minimum_quality_steps
  end

  test "a released compatibility row retains the census from its tagged index" do
    version = "1.0.0"
    row = Enum.find(ReleaseIdentity.compatibility(), &(version in &1.package_versions))

    live =
      "priv/conformance/index.json"
      |> File.read!()
      |> :json.decode()
      |> Map.fetch!("corpus_digest")

    assert row.verification_semantics == 6
    refute row.census_digest == live
    root = File.cwd!()

    assert :ok =
             ReleaseCompatibility.verify!(row, version, row.verification_semantics, live, root)

    assert_raise RuntimeError, ~r/compatibility census for 1\.0\.0/, fn ->
      stale = %{row | census_digest: "different"}
      ReleaseCompatibility.verify!(stale, version, row.verification_semantics, live, root)
    end
  end

  test "the current candidate records its live compatibility identity" do
    version = Mix.Project.config()[:version]
    semantics = ReleaseIdentity.verification_semantics()
    row = Enum.find(ReleaseIdentity.compatibility(), &(version in &1.package_versions))

    live =
      "priv/conformance/index.json"
      |> File.read!()
      |> :json.decode()
      |> Map.fetch!("corpus_digest")

    assert row.census_digest == live

    witnesses = Enum.flat_map(row.transitions, & &1.witnesses)

    assert Enum.any?(witnesses, fn group ->
             group.from == "chain_invalid" and group.to == "descriptor_key_invalid" and
               "chain-many-histories-first-party-error" in group.cases
           end)

    assert Enum.any?(witnesses, fn group ->
             group.from == "chain_invalid" and group.to == "invalid_syntax" and
               "chain-expanded-histories-before-revision-syntax" in group.cases
           end)

    assert :ok = ReleaseCompatibility.verify!(row, version, semantics, live, File.cwd!())
  end

  test "reverse differential rejects missing, stale, and incorrect witnesses" do
    baseline = "hex:1.0.0"

    named = %{
      "corpus_runner/new-case" => observation("chain.verify", success(%{})),
      "public_api/new-case" => observation("verify_chain", success(%{}))
    }

    old = %{named | "corpus_runner/new-case" => observation("chain.verify", "chain_invalid")}

    witness = %{
      entry_point: "corpus_runner",
      baselines: [baseline],
      cases: ["new-case"],
      from: "chain_invalid",
      to: "valid"
    }

    transition = %{
      class: :admission,
      direction: :red_to_green,
      operation: "chain.verify",
      description: "A case verifies after the change",
      witnesses: [witness]
    }

    row = %{transitions: [transition]}

    assert ReleaseCompatibility.verify_reverse!(row, baseline, old, named) == 1

    assert_raise RuntimeError,
                 ~r/unrecorded.*new-case.*baseline: "chain_invalid".*candidate: %\{/,
                 fn ->
                   ReleaseCompatibility.verify_reverse!(%{transitions: []}, baseline, old, named)
                 end

    assert_raise RuntimeError,
                 ~r/no longer firing.*new-case.*baseline: %\{.*candidate: %\{/,
                 fn ->
                   ReleaseCompatibility.verify_reverse!(row, baseline, named, named)
                 end

    wrong_code =
      Map.put(old, "corpus_runner/new-case", observation("chain.verify", "invalid_type"))

    assert_raise RuntimeError,
                 ~r/outcome drift.*new-case.*baseline: "invalid_type".*candidate: %\{/,
                 fn ->
                   ReleaseCompatibility.verify_reverse!(row, baseline, wrong_code, named)
                 end

    assert_raise RuntimeError, ~r/witness .* disagrees with red_to_green/, fn ->
      path = [:transitions, Access.at(0), :witnesses, Access.at(0), :to]
      wrong_direction = put_in(row, path, "invalid_type")
      ReleaseCompatibility.verify_reverse!(wrong_direction, baseline, old, named)
    end
  end

  test "reverse differential rejects swapped descriptor and signing witnesses" do
    descriptor_id = "descriptor-publication-successor"
    signing_id = "descriptor-publication-sign-successor"
    transitions = List.last(ReleaseIdentity.compatibility()).transitions
    descriptor = isolate_witness(transitions, descriptor_id)
    signing = isolate_witness(transitions, signing_id)
    row = %{transitions: [descriptor, signing]}

    mappings = [
      {"corpus_runner/" <> descriptor_id, "party_descriptor.verify"},
      {"corpus_runner/" <> signing_id, "signing.prepare"}
    ]

    before =
      Map.new(mappings, fn {key, op} -> {key, observation(op, "protected_header_invalid")} end)

    after_change = Map.new(mappings, fn {key, op} -> {key, observation(op, success(%{}))} end)
    assert ReleaseCompatibility.verify_reverse!(row, "hex:1.0.0", before, after_change) == 2

    swapped = %{
      transitions: [
        %{descriptor | witnesses: signing.witnesses},
        %{signing | witnesses: descriptor.witnesses}
      ]
    }

    assert_raise RuntimeError, ~r/does not name operation party_descriptor.verify/, fn ->
      ReleaseCompatibility.verify_reverse!(swapped, "hex:1.0.0", before, after_change)
    end
  end

  test "reverse differential checks both successful projections" do
    id = "legacy-unsigned-predecessor-leaves-no-governing-revision"
    transitions = List.last(ReleaseIdentity.compatibility()).transitions
    transition = isolate_witness(transitions, id)
    row = %{transitions: [transition]}
    [witness] = transition.witnesses
    key = "corpus_runner/" <> id
    before = %{key => observation(transition.operation, success(witness.outputs["before"]))}
    after_change = %{key => observation(transition.operation, success(witness.outputs["after"]))}

    assert ReleaseCompatibility.verify_reverse!(row, "hex:1.0.0", before, after_change) == 1

    assert_raise RuntimeError, ~r/unrecorded.*legacy-unsigned-predecessor/, fn ->
      ReleaseCompatibility.verify_reverse!(%{transitions: []}, "hex:1.0.0", before, after_change)
    end

    assert_raise RuntimeError, ~r/outcome drift.*legacy-unsigned-predecessor/, fn ->
      changed = %{key => observation(transition.operation, success(%{}))}
      ReleaseCompatibility.verify_reverse!(row, "hex:1.0.0", before, changed)
    end
  end

  test "reverse differential preserves nil in unchanged corpus outputs" do
    corpus = ReverseCorpus.load!("priv/conformance")
    ids = ["revision-no-bindings", "acceptance-same-signer-equivocation"]
    cases = Enum.filter(corpus.cases, &(&1["id"] in ids))
    checked = ReverseCorpus.checked!(%{corpus | cases: cases})

    assert %{"value" => %{"output" => %{"abp_binding" => nil}}} =
             checked["corpus_runner/revision-no-bindings"]

    assert %{"value" => %{"output" => %{"winner" => nil}}} =
             checked["corpus_runner/acceptance-same-signer-equivocation"]

    scratch = SeededMutation.temporary!("reverse-outcomes")
    path = Path.join(scratch, "outcomes.etf")

    try do
      ReverseCorpus.write_outcomes!(path, checked)
      published = ReverseCorpus.read_outcomes!(path)

      assert ReleaseCompatibility.verify_reverse!(
               %{transitions: []},
               "hex:1.0.0",
               published,
               checked
             ) == 0

      native = %{1 => {~U[2026-09-01 00:00:00Z], :none}, <<255>> => <<0, 255>>}
      ReverseCorpus.write_outcomes!(path, native)
      assert ReverseCorpus.read_outcomes!(path) === native
    after
      File.rm_rf!(scratch)
    end
  end

  test "reverse differential keeps the published replacement signing error" do
    id = "signing-assignment-departing-party"
    transitions = List.last(ReleaseIdentity.compatibility()).transitions
    transition = isolate_witness(transitions, id)
    row = %{transitions: [transition]}
    key = "corpus_runner/" <> id
    before = %{key => observation("signing.prepare", "invalid_type")}
    candidate = %{key => observation("signing.prepare", success(%{}))}

    assert ReleaseCompatibility.verify_reverse!(row, "hex:1.0.0", before, candidate) == 1

    assert_raise RuntimeError, ~r/outcome drift.*signing-assignment-departing-party/, fn ->
      skipped = %{key => observation("signing.prepare", "unsupported")}
      ReleaseCompatibility.verify_reverse!(row, "hex:1.0.0", skipped, candidate)
    end
  end

  test "qualification rejects npm-only witness drift from the pinned row" do
    row = List.last(ReleaseIdentity.compatibility())
    pinned = File.read!("priv/release-metadata.json")
    assert :ok = ReleaseCompatibility.verify_npm_witnesses!(row, pinned)

    index =
      Enum.find_index(row.transitions, fn transition ->
        transition.operation == "assemble_compact" and transition.direction == :red_to_red
      end)

    path = [:transitions, Access.at(index), :witnesses, Access.at(0), :from]
    assert get_in(row, path) == "algorithm_unsupported"
    drifted = put_in(row, path, "invalid_type")

    assert_raise RuntimeError, ~r/npm compatibility witnesses differ/, fn ->
      ReleaseCompatibility.verify_npm_witnesses!(drifted, pinned)
    end
  end

  test "a new package version requires the live corpus census" do
    version = "99.0.0"
    row = %{verification_semantics: 6, census_digest: "live", transitions: []}
    root = File.cwd!()

    assert :ok = ReleaseCompatibility.verify!(row, version, 6, "live", root)

    assert_raise RuntimeError, ~r/compatibility census for 99\.0\.0/, fn ->
      ReleaseCompatibility.verify!(row, version, 6, "different", root)
    end
  end

  test "compatibility rejects a passing verdict for an error code change" do
    row = %{
      verification_semantics: 6,
      census_digest: "live",
      transitions: [%{class: :error_code_change, direction: :green_to_red}]
    }

    assert_raise RuntimeError, ~r/incompatible release transition :error_code_change/, fn ->
      ReleaseCompatibility.verify!(row, "99.0.0", 6, "live", File.cwd!())
    end
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
             "scratch_green!(mutation.command, scratch)\n      SeededMutation.apply_once!(Path.join(scratch, mutation.path)"
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
      "test/**/*.exs"
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
      |> Enum.uniq()

    assert Enum.sort(mapped_mutations) == Enum.sort(@mutation_names)

    source_mutations =
      RequirementMap.source_mutation_names(File.read!("scripts/check_conformance_mutations.exs"))

    assert Enum.sort(source_mutations) == Enum.sort(@mutation_names)
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

  defp isolate_witness(transitions, id) do
    transition =
      Enum.find(transitions, fn transition ->
        Enum.any?(transition.witnesses, &(id in &1.cases))
      end)

    group = Enum.find(transition.witnesses, &(id in &1.cases))
    %{transition | witnesses: [%{group | cases: [id]}]}
  end

  defp observation(operation, value), do: %{"operation" => operation, "value" => value}
  defp success(output), do: %{"status" => "valid", "output" => output}

  defp shipped_files do
    "priv/conformance/**/*"
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Map.new(fn path -> {Path.relative_to(path, "priv/conformance"), File.read!(path)} end)
  end
end
