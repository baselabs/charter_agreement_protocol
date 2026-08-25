defmodule CharterAgreementProtocol.Conformance.CorpusTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.Conformance.Corpus
  alias CharterAgreementProtocol.ConformanceTest.Builder
  alias CharterAgreementProtocol.{DescriptorChain, Error, Limits, PartyDescriptor}

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

    assert length(verify_cases) == 6
    Enum.each(verify_cases, &assert_verify_case/1)
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

  defp projected_chain_result({:ok, chain}, %{"output" => expected}) do
    output = %{"topology" => Atom.to_string(chain.topology)}

    output =
      if Map.has_key?(expected, "positions") do
        positions =
          Map.new(chain.descriptors, fn facts ->
            {facts.descriptor_digest, Atom.to_string(facts.descriptor_position)}
          end)

        Map.put(output, "positions", positions)
      else
        output
      end

    output =
      if Map.has_key?(expected, "sibling_descriptors") do
        Map.put(output, "sibling_descriptors", chain.fork_evidence.sibling_descriptors)
      else
        output
      end

    %{"status" => "valid", "output" => output}
  end

  defp projected_chain_result({:error, %Error{code: code}}, _expectation),
    do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp deny(map, code) do
    assert {:error, %Error{code: ^code}} = Corpus.load(map)
  end
end
