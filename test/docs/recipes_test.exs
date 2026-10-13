defmodule CharterAgreementProtocol.Docs.RecipesTest do
  @moduledoc """
  Runs the Elixir blocks in `docs/guides/recipes.md`, `docs/guides/integration.md`,
  `docs/guides/error-codes.md` and `docs/guides/upgrading-verification-identity.md`, so a
  code block on any of them that stops working fails the suite.

  The recipes page has one setup section followed by recipes, each under its own `##`
  heading. The test runs the setup with each recipe on its own, and the whole page top
  to bottom. The other pages run top to bottom. Blocks are evaluated in order with
  one binding and one environment, so variables and aliases carry from block to block
  the way they do in iex. After each section the test checks the results it promises,
  including the claims its prose makes.

  `CAP_RECIPES_PATH`, `CAP_INTEGRATION_PATH`, `CAP_ERRORS_PATH` and `CAP_UPGRADE_PATH`
  point the test at another copy of a page. They exist so a broken copy can be run to show the test fails; leave them unset
  otherwise.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias CharterAgreementProtocol, as: CAP
  alias CharterAgreementProtocol.{Algorithm, Error, Facts, Limits, ReleaseIdentity}
  alias CharterAgreementProtocol.Capability.Profile

  @recipes_page "docs/guides/recipes.md"
  @integration_page "docs/guides/integration.md"
  @errors_page "docs/guides/error-codes.md"
  @upgrade_page "docs/guides/upgrading-verification-identity.md"

  @setup "Set up two parties and an accepted charter"

  @recipes [
    "Verify a charter view you received",
    "Narrow what a deployment accepts",
    "Compose and sign a receipt",
    "Rotate a party's signing key",
    "Terminate the charter",
    "Repair a contested fork",
    "Handle errors at the call boundary",
    "Record what you verified under",
    "Run the conformance corpus in your CI"
  ]

  describe "recipes" do
    test "the page holds the setup and the recipes this test checks, in order" do
      assert Enum.map(sections(recipes_path()), &elem(&1, 0)) == [@setup | @recipes]
    end

    test "every recipe runs on its own after the setup" do
      path = recipes_path()
      [{@setup, setup_blocks} | recipes] = sections(path)

      for {heading, blocks} <- recipes do
        {state, _output} = run(setup_blocks, new_state(path), path)
        {state, output} = run(blocks, state, path)
        check(heading, Map.new(elem(state, 0)), output)
      end
    end

    test "the whole page runs from top to bottom" do
      path = recipes_path()

      Enum.reduce(sections(path), new_state(path), fn {heading, blocks}, state ->
        {state, output} = run(blocks, state, path)
        check(heading, Map.new(elem(state, 0)), output)
        state
      end)
    end
  end

  describe "integration guide" do
    test "the page runs from top to bottom" do
      path = integration_path()
      checked = Enum.map(sections(path), &elem(&1, 0))

      assert checked == [
               "At boot: check what the runtime can verify",
               "Choose a profile",
               "Choose and pin limits",
               "Verify what you receive",
               "Ask which revision governs, and at what time",
               "Log errors safely",
               "Verify after you produce"
             ]

      Enum.reduce(sections(path), new_state(path), fn {heading, blocks}, state ->
        {state, output} = run(blocks, state, path)
        check_integration(heading, Map.new(elem(state, 0)), output)
        state
      end)
    end

    test "the limits table matches the compiled defaults and maximums" do
      rows =
        Regex.scan(
          ~r/^\| `(max_[a-z_]+)` \| ([\d,]+) \| ([\d,]+) \|/m,
          File.read!(integration_path()),
          capture: :all_but_first
        )

      table =
        Map.new(rows, fn [field, default, maximum] ->
          {String.to_existing_atom(field), {number(default), number(maximum)}}
        end)

      assert Map.keys(table) |> Enum.sort() == Enum.sort(Limits.fields())

      for field <- Limits.fields() do
        assert table[field] ==
                 {Map.fetch!(Limits.default(), field), Map.fetch!(Limits.maximums(), field)}
      end
    end
  end

  describe "error page" do
    test "the example handler runs and classifies errors as described" do
      path = errors_path()
      [{"Handle errors", blocks}] = sections(path, "# ")
      {{binding, _env}, _output} = run(blocks, new_state(path), path)
      b = Map.new(binding)

      assert b.result == {:rejected, :missing_required}
      assert b.handle.({:ok, :facts}) == {:ok, :facts}

      assert b.handle.({:error, Error.new(:algorithm_unsupported_on_substrate, ["signature"])}) ==
               :verify_on_a_capable_runtime

      assert_raise ArgumentError, ~r/bad CAP configuration: invalid_limits at limits/, fn ->
        b.handle.(Limits.new(max_depth: -1))
      end
    end

    test "the main tables explain every error code exactly once" do
      [main, _appendix] = errors_path() |> File.read!() |> String.split("## Appendix")
      explained = Regex.scan(~r/^\| `:([a-z0-9_]+)` \|/m, main, capture: :all_but_first)
      explained = List.flatten(explained)

      assert Enum.sort(explained) == Error.codes() |> Enum.map(&Atom.to_string/1) |> Enum.sort()
    end
  end

  describe "upgrade guide" do
    test "the semantics example runs and the release table matches the published rows" do
      path = upgrade_path()
      [{_title, blocks}] = sections(path, "# ")
      {{binding, _env}, _output} = run(blocks, new_state(path), path)
      b = Map.new(binding)

      assert b.current == ReleaseIdentity.verification_semantics()

      published =
        ReleaseIdentity.compatibility()
        |> Enum.group_by(& &1.verification_semantics, & &1.package_versions)
        |> Map.new(fn {semantics, versions} -> {semantics, List.flatten(versions)} end)

      assert Map.new(b.releases, fn {semantics, _versions, _count} -> {semantics, nil} end)
             |> Map.keys()
             |> Enum.sort() == published |> Map.keys() |> Enum.sort()

      table =
        ~r/^\| (\d+) \| (\d+\.\d+\.\d+(?:, \d+\.\d+\.\d+)*) \|/m
        |> Regex.scan(File.read!(path), capture: :all_but_first)
        |> Map.new(fn [semantics, versions] ->
          {String.to_integer(semantics), String.split(versions, ", ")}
        end)

      assert table == published
    end
  end

  defp check(@setup, b, _output) do
    assert b.chain_facts.accepted_revision_digests == [b.revision_digest]
    assert b.chain_facts.charter_id == b.charter_id
    assert b.chain_facts.not_verified == Facts.not_verified_floor()
    assert length(b.acceptance_compacts) == 2

    # The prose: the default producer refuses claims that name another revision.
    descriptor_claims = %{
      "protocol_revision" => 1,
      "descriptor_number" => 1,
      "verification_keys" => [
        %{
          "key_id" => "issuer-key",
          "algorithm" => "Ed25519",
          "public_key" => CharterAgreementProtocol.Base64Url.encode(b.issuer_public),
          "status" => "active"
        }
      ],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-10-01T09:00:00Z"
    }

    assert {:error, %Error{code: :signing_input_invalid}} =
             CAP.descriptor_signing_input(%{"kid" => "issuer-key", "claims" => descriptor_claims})
  end

  defp check("Verify a charter view you received", b, _output) do
    assert b.governing == {:governed_by, b.revision_digest}
    assert b.chain_facts.chain_topology == :linear
    assert inspect(b.chain_facts) == "#CharterAgreementProtocol.ChainFacts<redacted>"
    assert CAP.governing_revision(b.chain_facts, ~U[2026-09-30 00:00:00Z]) == {:ok, :none}
  end

  defp check("Narrow what a deployment accepts", b, _output) do
    assert %Profile{algorithms: ["Ed25519"], revisions: {2, 3}} = b.ed25519_only
    assert %Profile{algorithms: ["ML-DSA-65"]} = b.ml_dsa_only
  end

  defp check("Compose and sign a receipt", b, _output) do
    facts = b.receipt_facts
    assert facts.governing_match == :match
    assert facts.chain_conflict == :none
    assert facts.signing_key_id == "issuer-key"
    assert {facts.protocol_revision, facts.alg} == {2, "Ed25519"}

    revision_only = b.revision_only
    assert revision_only.governing_match == :undetermined
    assert revision_only.signing_key_id == nil
    assert :signature in revision_only.not_verified
  end

  defp check("Rotate a party's signing key", b, _output) do
    assert b.issuer_history.topology == :linear

    assert Enum.map(b.issuer_history.descriptors, & &1.descriptor_position) == [
             :superseded,
             :head
           ]

    assert b.successor_facts.party_id == b.issuer_digest
    assert b.successor_facts.signing_key_id == "issuer-key"

    # The prose: a successor signed only by its own new key is rejected.
    {:ok, input} =
      CAP.descriptor_signing_input(%{"kid" => "issuer-key-2", "claims" => b.successor_claims})

    self_signed = b.sign.(input, b.new_private)

    assert {:error, %Error{code: :descriptor_key_invalid}} =
             CAP.verify_descriptor(self_signed, b.current, b.limits)

    # The integration guide: acceptances naming the older descriptor still verify,
    # and their facts report the descriptor as superseded.
    {:ok, rotated} =
      CAP.verify_chain(
        [b.revision_bytes],
        b.acceptance_compacts,
        [b.issuer_descriptor, b.successor, b.acceptor_descriptor],
        [],
        b.limits
      )

    assert Map.new(rotated.acceptance_facts, &{&1.party_role, &1.descriptor_position}) ==
             %{"issuer" => :superseded, "acceptor" => :head}
  end

  defp check("Terminate the charter", b, _output) do
    assert b.before_end == {:ok, b.revision_digest}
    assert b.at_end == {:ok, :none}

    # The prose: the producer refuses a notice the revision does not support.
    for overrides <- [
          %{"reason_code" => "convenience"},
          %{"effective_at" => "2026-09-30T00:00:00Z", "issued_at" => "2026-09-29T00:00:00Z"}
        ] do
      claims = Map.merge(b.termination_claims, overrides)

      assert {:error, %Error{code: :signing_refused}} =
               CAP.termination_signing_input(
                 %{"kid" => "issuer-key", "claims" => claims},
                 b.full_view
               )
    end
  end

  defp check("Repair a contested fork", b, _output) do
    assert Enum.sort(Enum.map(b.forked.fork_evidence, & &1.kind)) ==
             [:equivocal_acceptances, :equivocal_acceptances, :sibling_revisions]

    assert b.governing_after_repair == b.repair_digest

    # The prose: the producer refuses an acceptance whose ancestry leaves out an
    # accepted head. This revision 3 follows the USD branch and drops the EUR head.
    {partial_bytes, partial_digest} =
      b.amend.("Supplier terms, USD only\n", %{
        "revision_number" => 3,
        "prev_revision_digest" => b.usd_digest,
        "effective_from" => "2026-10-06T00:00:00Z"
      })

    {:ok, view} =
      CAP.build_set(
        [b.revision_bytes, b.usd_bytes, b.eur_bytes, partial_bytes],
        b.acceptances,
        [],
        b.descriptor_compacts
      )

    claims = b.acceptance_claims.(3, partial_digest, b.usd_digest, b.issuer_digest, "issuer")

    assert {:error, %Error{code: :signing_refused}} =
             CAP.acceptance_signing_input(%{"kid" => "issuer-key", "claims" => claims}, view)
  end

  defp check("Handle errors at the call boundary", b, output) do
    assert b.rejected_code == :signature_invalid
    assert output =~ "charter view rejected: signature_invalid at compact_jws.signature"
  end

  defp check("Record what you verified under", b, _output) do
    record = b.verified_under
    manifest = b.manifest

    assert record["verification_semantics_version"] == ReleaseIdentity.verification_semantics()
    assert record["verification_semantics_version"] == manifest["verification_semantics_version"]
    assert record["limits"] == manifest["limits"]["default"]
    assert record["signature_registry_digest"] == manifest["signature_registry_digest"]

    assert record["signature_registry_digest"] ==
             CharterAgreementProtocol.Digest.to_tagged(Algorithm.registry_digest())

    # One revision (unsigned, so `alg` is nil), two descriptors, two acceptances.
    assert Enum.map(record["artifacts"], &{&1["protocol_revision"], &1["alg"]}) ==
             [{2, nil}, {2, "Ed25519"}, {2, "Ed25519"}, {2, "Ed25519"}, {2, "Ed25519"}]

    digests = Enum.map(record["artifacts"], & &1["digest"])
    assert length(Enum.uniq(digests)) == 5
    assert Enum.all?(digests, &(&1 =~ ~r/\Asha-256:/))

    assert Enum.all?(["spec_digest", "corpus_digest"], &(record[&1] =~ ~r/\Asha-256:/))
    assert is_binary(record["package_version"])
  end

  defp check("Run the conformance corpus in your CI", b, output) do
    assert b.exit_status == 0
    assert output =~ ~s("agreement":true)
    assert output =~ ~s("disagreed":0)
  end

  defp check_integration("At boot: check what the runtime can verify", b, _output) do
    names = Enum.map(Algorithm.registry(), & &1.name)
    assert Enum.sort(b.verifiable ++ b.unverifiable) == Enum.sort(names)
    assert "Ed25519" in b.verifiable
    assert is_list(b.report.linked_crypto)
  end

  defp check_integration("Choose a profile", b, _output) do
    assert Profile.valid?(b.profile)
    assert b.profile.algorithms == b.verifiable
    assert Profile.full() == elem(Profile.new(), 1)
  end

  defp check_integration("Choose and pin limits", b, _output) do
    assert %Limits{max_bytes: 262_144, max_artifact_set_items: 256} = b.limits
    assert b.limits.max_depth == Limits.default().max_depth
  end

  defp check_integration("Verify what you receive", b, _output) do
    assert b.chain_facts.accepted_revision_digests == [b.chain_facts.charter_id]

    # The prose: revisions {2, 3} refuses revision-1 artifacts.
    {:ok, no_revision_1} = Profile.new(revisions: {2, 3})
    received = b.received

    assert {:error, %Error{code: :revision_outside_profile}} =
             CAP.verify_chain(
               received["revisions"],
               received["acceptances"],
               received["descriptors"],
               received["terminations"],
               b.limits,
               no_revision_1
             )
  end

  defp check_integration("Ask which revision governs, and at what time", b, _output) do
    assert b.now == {:governed_by, b.chain_facts.charter_id}
    assert b.before_start == :not_in_force

    # The prose: a Timestamp works, another time zone and a string do not.
    {:ok, timestamp} = CharterAgreementProtocol.Timestamp.parse("2026-10-01T00:00:00Z")
    assert b.which_governs.(b.chain_facts, timestamp) == b.now

    paris = %DateTime{
      year: 2026,
      month: 10,
      day: 1,
      hour: 2,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      time_zone: "Europe/Paris",
      zone_abbr: "CEST",
      utc_offset: 3600,
      std_offset: 3600
    }

    assert b.which_governs.(b.chain_facts, paris) == {:rejected, :governing_invalid}
    assert b.which_governs.(b.chain_facts, "2026-10-01T00:00:00Z") == {:rejected, :invalid_type}
  end

  defp check_integration("Log errors safely", b, output) do
    assert %Error{code: :non_canonical_bytes, subject: ["charter_revision"], detail: nil} =
             b.error

    assert output =~ "charter view rejected: non_canonical_bytes at charter_revision"
  end

  defp check_integration("Verify after you produce", b, _output) do
    assert b.descriptor_facts.signing_key_id == "party-key"

    assert {:error, %Error{code: :signature_invalid}} =
             CAP.verify_descriptor(b.wrong, nil, b.limits)
  end

  defp number(text), do: text |> String.replace(",", "") |> String.to_integer()

  defp new_state(path), do: {[], Code.env_for_eval(file: path)}

  # Returns the new state and everything the blocks wrote to stdout or the log.
  defp run(blocks, state, path) do
    {{state, log}, io} =
      with_io(fn -> with_log(fn -> Enum.reduce(blocks, state, &eval(&1, &2, path)) end) end)

    {state, io <> log}
  end

  defp eval({code, line}, {binding, env}, path) do
    quoted = Code.string_to_quoted!(code, file: path, line: line)
    {_value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
    {binding, env}
  end

  # [{heading, [{code, first_line}]}] for each `##` section holding Elixir blocks.
  defp sections(path, prefix \\ "## ") do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, nil}, fn
      {"```elixir", line}, {sections, heading, nil} ->
        {sections, heading, {line + 1, []}}

      {"```", _line}, {sections, heading, {first, lines}} ->
        block = {lines |> Enum.reverse() |> Enum.join("\n"), first}
        {add_block(sections, heading, block), heading, nil}

      {text, _line}, {sections, heading, {first, lines}} ->
        {sections, heading, {first, [text | lines]}}

      {text, _line}, {sections, _heading, nil} = acc ->
        if String.starts_with?(text, prefix),
          do: {sections, String.replace_prefix(text, prefix, ""), nil},
          else: acc
    end)
    |> then(fn {sections, _heading, nil} -> Enum.reverse(sections) end)
    |> Enum.map(fn {heading, blocks} -> {heading, Enum.reverse(blocks)} end)
  end

  defp add_block([{heading, blocks} | rest], heading, block),
    do: [{heading, [block | blocks]} | rest]

  defp add_block(sections, heading, block), do: [{heading, [block]} | sections]

  defp recipes_path, do: page("CAP_RECIPES_PATH", @recipes_page)
  defp integration_path, do: page("CAP_INTEGRATION_PATH", @integration_page)
  defp errors_path, do: page("CAP_ERRORS_PATH", @errors_page)
  defp upgrade_path, do: page("CAP_UPGRADE_PATH", @upgrade_page)

  defp page(variable, relative),
    do: System.get_env(variable, Path.expand(Path.join("../..", relative), __DIR__))
end
