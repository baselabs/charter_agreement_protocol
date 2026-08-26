defmodule CharterAgreementProtocol.Conformance.CorpusTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.Conformance.Corpus
  alias CharterAgreementProtocol.ConformanceTest.Builder

  alias CharterAgreementProtocol.{
    Acceptance,
    Chain,
    CharterRevision,
    DescriptorChain,
    Error,
    Limits,
    PartyDescriptor,
    Receipt,
    TerminationNotice
  }

  defp minimal, do: Builder.build()

  test "the compiled-floor corpus loads with a recomputed identity" do
    assert {:ok, %Corpus{identity: "sha-256:" <> body, cases: cases}} = Corpus.load(minimal())
    assert byte_size(body) == 43
    assert length(cases) == length(Builder.minimal_cases())
  end

  test "non-map, missing, malformed, and non-canonical indexes fail closed" do
    deny(:not_a_map, :corpus_index_invalid)
    deny(Map.delete(minimal(), "index.json"), :corpus_index_invalid)
    deny(Map.put(minimal(), "index.json", "{}"), :corpus_index_invalid)
    deny(Map.put(minimal(), "index.json", "null"), :corpus_index_invalid)

    padded = Map.update!(minimal(), "index.json", &(&1 <> " "))
    deny(padded, :corpus_index_invalid)

    non_list_files = Builder.update_index(minimal(), &Map.put(&1, "files", "not_a_list"))
    deny(non_list_files, :corpus_index_invalid)

    non_map_file = Builder.update_index(minimal(), &Map.put(&1, "files", ["not_a_map"]))
    deny(non_map_file, :corpus_index_invalid)
  end

  test "a stale self-digest fails closed" do
    tampered =
      Builder.update_index(
        minimal(),
        &Map.put(&1, "corpus_digest", "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
        redigest: false
      )

    deny(tampered, :corpus_index_invalid)
  end

  test "declared and observed file sets must be exactly equal" do
    deny(Map.delete(minimal(), "cases/foundation.json"), :corpus_file_set_mismatch)
    deny(Map.put(minimal(), "cases/extra.json", "{}"), :corpus_file_set_mismatch)
  end

  test "case-file bytes are independently hash-bound" do
    tampered = Map.update!(minimal(), "cases/foundation.json", &(&1 <> " "))
    deny(tampered, :corpus_hash_mismatch)
  end

  test "per-file and total counts must equal observed cases" do
    total = Builder.update_index(minimal(), &Map.put(&1, "total_cases", 999))
    deny(total, :corpus_count_mismatch)

    file =
      Builder.update_index(minimal(), fn index ->
        Map.update!(index, "files", fn [entry] -> [%{entry | "cases" => 999}] end)
      end)

    deny(file, :corpus_count_mismatch)
  end

  test "case IDs are non-empty and globally unique" do
    [first | rest] = Builder.minimal_cases()
    duplicate = Builder.build([first, first | rest])
    deny(duplicate, :corpus_case_id_duplicate)

    empty = Builder.build([Map.put(first, "id", "") | rest])
    deny(empty, :corpus_case_invalid)
  end

  test "case shape, known surface, and known class are closed" do
    [first | rest] = Builder.minimal_cases()

    for changed <- [
          Map.delete(first, "input"),
          Map.put(first, "surface", "unknown.surface"),
          Map.put(first, "class", "unknown_class")
        ] do
      deny(Builder.build([changed | rest]), :corpus_case_invalid)
    end

    map = minimal()
    case_file = map |> Map.fetch!("cases/foundation.json") |> Builder.decode!()
    malformed = Map.update!(case_file, "cases", fn [_first | cases] -> [1 | cases] end)
    deny(Builder.replace_case_file(map, malformed), :corpus_case_invalid)

    deny(Builder.replace_case_file(map, %{}), :corpus_case_invalid)
  end

  test "a valid expectation must project an output, not merely say green" do
    cases =
      Enum.map(Builder.minimal_cases(), fn
        %{"class" => "valid"} = one -> Map.put(one, "expect", %{"status" => "valid"})
        one -> one
      end)

    deny(Builder.build(cases), :corpus_case_invalid)
  end

  test "empty and all-not-applicable corpora cannot load" do
    deny(Builder.build([]), :corpus_empty)

    all_not_applicable =
      Builder.update_index(minimal(), fn index ->
        applicability =
          Map.new(Corpus.surfaces(), fn surface ->
            reason = Corpus.floor()[surface].n_a
            {surface, Map.new(Corpus.classes(), &{&1, %{"n_a" => reason}})}
          end)

        Map.put(index, "applicability", applicability)
      end)

    deny(all_not_applicable, :corpus_applicability_incomplete)
  end

  test "required counts equal observations and not-applicable reasons are non-empty" do
    surface = hd(Corpus.surfaces())
    required_class = hd(Corpus.floor()[surface].required)
    optional_class = Enum.find(Corpus.classes(), &(&1 not in Corpus.floor()[surface].required))

    wrong_count =
      Builder.update_index(minimal(), fn index ->
        put_in(index, ["applicability", surface, required_class], 999)
      end)

    deny(wrong_count, :corpus_applicability_incomplete)

    empty_reason =
      Builder.update_index(minimal(), fn index ->
        put_in(index, ["applicability", surface, optional_class], %{"n_a" => ""})
      end)

    deny(empty_reason, :corpus_applicability_incomplete)

    missing_surface =
      Builder.update_index(minimal(), fn index ->
        update_in(index, ["applicability"], &Map.delete(&1, surface))
      end)

    deny(missing_surface, :corpus_applicability_incomplete)

    smuggled_key =
      Builder.update_index(minimal(), fn index ->
        put_in(index, ["applicability", surface, optional_class], %{
          "n_a" => "reason",
          "smuggled" => "note"
        })
      end)

    deny(smuggled_key, :corpus_applicability_incomplete)
  end

  test "unexpected JSON primitive types in the index fail as typed corpus errors" do
    for primitive <- [nil, true, 1.5] do
      tampered =
        Builder.update_index(minimal(), fn index ->
          Map.put(index, "applicability", %{"unexpected" => primitive})
        end)

      deny(tampered, :corpus_applicability_incomplete)
    end
  end

  test "the shipped corpus loads through the pure map interface" do
    assert {:ok, %Corpus{cases: cases}} = Corpus.load(shipped_files())

    assert Enum.any?(cases, fn one ->
             one["surface"] == "party_descriptor.verify" and
               one["expect"]["status"] == "invalid" and
               one["class"] == "signature_invalid"
           end)

    assert Enum.any?(cases, fn one ->
             one["surface"] == "descriptor_chain.verify" and
               one["expect"]["status"] == "invalid" and
               one["class"] in ["signature_invalid", "chain_invalid"]
           end)

    assert_verify_surface_expectations(cases)
    assert_revision_expectations(cases)
    assert_acceptance_expectations(cases)
    assert_termination_expectations(cases)
    assert_chain_expectations(cases)
    assert_receipt_expectations(cases)
  end

  defp shipped_files do
    "priv/conformance/**/*"
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Map.new(fn path -> {Path.relative_to(path, "priv/conformance"), File.read!(path)} end)
  end

  defp assert_verify_surface_expectations(cases) do
    verify_cases =
      Enum.filter(
        cases,
        &(&1["surface"] in ["party_descriptor.verify", "descriptor_chain.verify"])
      )

    assert length(verify_cases) == 15
    Enum.each(verify_cases, &assert_verify_case/1)
  end

  defp assert_revision_expectations(cases) do
    revision_cases = Enum.filter(cases, &(&1["surface"] == "charter_revision.decode"))
    assert length(revision_cases) == 15

    Enum.each(revision_cases, fn one ->
      actual = CharterRevision.decode(one["input"]["text"], Limits.default())
      assert projected_revision_result(actual) == one["expect"]
    end)
  end

  defp projected_revision_result({:ok, revision}) do
    [binding] = revision.abp_bindings

    %{
      "status" => "valid",
      "output" => %{
        "revision_digest" => CharterRevision.digest(revision),
        "revision_number" => revision.revision_number,
        "precedence_declaration" => Atom.to_string(revision.precedence_declaration),
        "abp_binding" => %{
          "blueprint_id" => binding.blueprint_id,
          "release_number" => binding.release_number,
          "content_digest" => binding.content_digest,
          "deployment_digest" => binding.deployment_digest
        }
      }
    }
  end

  defp projected_revision_result({:error, %Error{code: code}}),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp assert_acceptance_expectations(cases) do
    acceptance_cases = Enum.filter(cases, &String.starts_with?(&1["surface"], "acceptance."))
    assert length(acceptance_cases) == 7
    Enum.each(acceptance_cases, &assert_acceptance_case/1)
  end

  defp assert_acceptance_case(%{"surface" => "acceptance.verify"} = one) do
    input = one["input"]
    {:ok, revision} = CharterRevision.decode(input["revision_text"], Limits.default())
    {:ok, chain} = DescriptorChain.verify(input["descriptor_compacts"], Limits.default())
    actual = Acceptance.verify(input["compact"], revision, chain, Limits.default())
    assert projected_acceptance_result(actual) == one["expect"]
  end

  defp assert_acceptance_case(%{"surface" => "acceptance.equivocation"} = one) do
    input = one["input"]
    {:ok, chain} = DescriptorChain.verify(input["descriptor_compacts"], Limits.default())

    facts =
      Enum.map(input["signed_revisions"], fn signed ->
        {:ok, revision} = CharterRevision.decode(signed["revision_text"], Limits.default())
        {:ok, facts} = Acceptance.verify(signed["compact"], revision, chain, Limits.default())
        facts
      end)

    actual = Acceptance.equivocation(Enum.at(facts, 0), Enum.at(facts, 1))
    assert projected_equivocation_result(actual) == one["expect"]
  end

  defp projected_acceptance_result({:ok, facts}) do
    %{
      "status" => "valid",
      "output" => %{
        "acceptance_digest" => facts.acceptance_digest,
        "revision_digest" => facts.revision_digest,
        "party_descriptor_digest" => facts.party_descriptor_digest,
        "descriptor_position" => Atom.to_string(facts.descriptor_position)
      }
    }
  end

  defp projected_acceptance_result({:error, %Error{code: code}}),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp assert_termination_expectations(cases) do
    termination_cases = Enum.filter(cases, &(&1["surface"] == "termination.verify"))
    assert length(termination_cases) == 4

    Enum.each(termination_cases, fn one ->
      input = one["input"]
      {:ok, revision} = CharterRevision.decode(input["revision_text"], Limits.default())
      {:ok, chain} = DescriptorChain.verify(input["descriptor_compacts"], Limits.default())
      actual = TerminationNotice.verify(input["compact"], revision, chain, Limits.default())
      assert projected_termination_result(actual) == one["expect"]
    end)
  end

  defp projected_termination_result({:ok, facts}) do
    %{
      "status" => "valid",
      "output" => %{
        "termination_digest" => facts.termination_digest,
        "governing_revision_digest" => facts.governing_revision_digest,
        "party_descriptor_digest" => facts.party_descriptor_digest,
        "reason_code" => facts.reason_code,
        "descriptor_position" => Atom.to_string(facts.descriptor_position)
      }
    }
  end

  defp projected_termination_result({:error, %Error{code: code}}),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp assert_chain_expectations(cases) do
    chain_cases =
      Enum.filter(cases, &(&1["surface"] in ["chain.verify", "governing_revision"]))

    assert length(chain_cases) == 5
    Enum.each(chain_cases, &assert_chain_case/1)
  end

  defp assert_chain_case(%{"surface" => "chain.verify"} = one) do
    actual = verify_chain_input(one["input"])
    assert projected_set_result(actual) == one["expect"]
  end

  defp assert_chain_case(%{"surface" => "governing_revision"} = one) do
    input = one["input"]
    {:ok, facts} = verify_chain_input(input)

    governing =
      Enum.map(input["queries"], fn query ->
        {:ok, at, 0} = DateTime.from_iso8601(query["at"])
        {:ok, result} = Chain.governing_revision(facts, at)
        if is_atom(result), do: Atom.to_string(result), else: result
      end)

    assert %{"status" => "valid", "output" => %{"governing_revisions" => governing}} ==
             one["expect"]
  end

  defp verify_chain_input(input) do
    Chain.verify(
      input["revisions"],
      input["acceptances"],
      input["descriptors"],
      input["terminations"],
      Limits.default()
    )
  end

  defp projected_set_result({:ok, facts}) do
    %{
      "status" => "valid",
      "output" => %{
        "charter_id" => facts.charter_id,
        "topology" => Atom.to_string(facts.chain_topology),
        "accepted_revision_digests" => facts.accepted_revision_digests,
        "superseded_revision_digests" => facts.superseded_revision_digests
      }
    }
  end

  defp projected_set_result({:error, %Error{code: code}}),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp assert_receipt_expectations(cases) do
    receipt_cases = Enum.filter(cases, &(&1["surface"] == "receipt.verify"))
    assert length(receipt_cases) == 10

    Enum.each(receipt_cases, fn one ->
      input = one["input"]
      {:ok, chain} = verify_chain_input(input["chain"])
      actual = Receipt.verify(input["compact"], chain, Limits.default())
      assert projected_receipt_result(actual) == one["expect"]
    end)
  end

  defp projected_receipt_result({:ok, facts}) do
    %{
      "status" => "valid",
      "output" => %{
        "receipt_digest" => facts.receipt_digest,
        "revision_number" => facts.revision_number,
        "revision_digest" => facts.revision_digest,
        "decision" => Atom.to_string(facts.decision),
        "outcome" => Atom.to_string(facts.outcome),
        "chain_conflict" => Atom.to_string(facts.chain_conflict),
        "governing_match" => Atom.to_string(facts.governing_match),
        "deployment_digest_matched" => facts.deployment_digest_matched,
        "optional_extensions_retained" => facts.optional_extensions_retained
      }
    }
  end

  defp projected_receipt_result({:error, %Error{code: code}}),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp projected_equivocation_result({:error, %Error{code: code}}),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp projected_equivocation_result({:ok, evidence}) do
    %{
      "status" => "valid",
      "output" => %{
        "kind" => Atom.to_string(evidence.kind),
        "revision_number" => evidence.revision_number,
        "revision_digests" => evidence.revision_digests,
        "winner" => evidence.winner
      }
    }
  end

  defp assert_verify_case(%{"surface" => "party_descriptor.verify"} = one) do
    actual = PartyDescriptor.verify(one["input"]["compact"], nil, Limits.default())

    assert projected_party_result(actual) == one["expect"]
  end

  defp assert_verify_case(%{"surface" => "descriptor_chain.verify"} = one) do
    actual = DescriptorChain.verify(one["input"]["compacts"], Limits.default())

    assert projected_chain_result(actual, one["expect"]) == one["expect"]
  end

  defp projected_party_result({:ok, facts}) do
    %{
      "status" => "valid",
      "output" => %{
        "descriptor_digest" => facts.descriptor_digest,
        "party_id" => facts.party_id,
        "descriptor_number" => facts.descriptor_number
      }
    }
  end

  defp projected_party_result({:error, %Error{code: code}}),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp projected_chain_result({:ok, chain}, _expectation) do
    positions =
      Map.new(chain.descriptors, fn facts ->
        {facts.descriptor_digest, Atom.to_string(facts.descriptor_position)}
      end)

    siblings = if chain.fork_evidence, do: chain.fork_evidence.sibling_descriptors, else: []

    %{
      "status" => "valid",
      "output" => %{
        "topology" => Atom.to_string(chain.topology),
        "positions" => positions,
        "sibling_descriptors" => siblings
      }
    }
  end

  defp projected_chain_result({:error, %Error{code: code}}, _expectation),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp deny(map, code) do
    assert {:error, %Error{code: ^code}} = Corpus.load(map)
  end
end
