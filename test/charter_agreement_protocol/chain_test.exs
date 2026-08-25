defmodule CharterAgreementProtocol.ChainTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    AcceptanceFixture,
    ArtifactSet,
    Chain,
    ChainFacts,
    ChainFixture,
    CharterRevisionFixture,
    DescriptorFacts,
    DescriptorFixture,
    Error,
    Facts,
    ForkEvidence,
    Limits,
    RevisionFacts,
    TerminationFacts,
    TerminationFixture
  }

  @not_verified ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth legal_validity term_satisfaction view_completeness counterparty_view wall_clock)a

  test "verifies dual assent and computes start-inclusive temporal precedence" do
    setup = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)

    assert {:ok, %ChainFacts{} = facts} =
             CharterAgreementProtocol.verify_chain(
               [setup.genesis.bytes],
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    assert facts.chain_topology == :linear
    assert facts.accepted_revision_digests == [setup.genesis.digest]
    assert facts.fork_evidence == []
    assert facts.not_verified == @not_verified
    assert inspect(facts) == "#CharterAgreementProtocol.ChainFacts<redacted>"

    assert {:ok, :none} =
             CharterAgreementProtocol.governing_revision(facts, at!("2026-08-25T11:59:59Z"))

    assert {:ok, setup.genesis.digest} ==
             CharterAgreementProtocol.governing_revision(facts, at!("2026-08-25T12:00:00Z"))
  end

  test "requires both bound roles and advances to the highest effective accepted revision" do
    setup = ChainFixture.base()
    revision_2 = ChainFixture.successor(setup.genesis, 2)

    one_sided = ChainFixture.acceptance(setup.genesis, setup.issuer, "issuer")

    assert {:ok, facts} =
             Chain.verify(
               [setup.genesis.bytes],
               [one_sided.compact],
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    assert facts.accepted_revision_digests == []
    assert {:ok, :none} = Chain.governing_revision(facts, at!("2026-08-26T00:00:00Z"))

    acceptances =
      ChainFixture.dual_acceptances(setup.genesis, setup) ++
        ChainFixture.dual_acceptances(revision_2, setup)

    assert {:ok, facts} =
             Chain.verify(
               [setup.genesis.bytes, revision_2.bytes],
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    assert {:ok, setup.genesis.digest} ==
             Chain.governing_revision(facts, at!("2026-08-25T12:00:00Z"))

    assert {:ok, revision_2.digest} ==
             Chain.governing_revision(facts, at!("2026-08-25T12:00:01Z"))
  end

  test "returns contested facts for fully accepted siblings and never tie-breaks" do
    setup = ChainFixture.base()
    left = ChainFixture.successor(setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(setup.genesis, 2, legal_text: "right\n")

    acceptances =
      [setup.genesis, left, right]
      |> Enum.flat_map(&ChainFixture.dual_acceptances(&1, setup))

    assert {:ok, %ChainFacts{chain_topology: :forked} = facts} =
             Chain.verify(
               Enum.map([setup.genesis, left, right], & &1.bytes),
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    assert Enum.any?(facts.fork_evidence, fn evidence ->
             evidence.kind == :sibling_revisions and
               evidence.revision_digests == Enum.sort([left.digest, right.digest])
           end)

    assert {:ok, :contested} =
             Chain.governing_revision(facts, at!("2026-08-25T12:00:01Z"))
  end

  test "bilateral supersession repairs a sibling contest" do
    setup = ChainFixture.base()
    left = ChainFixture.successor(setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(setup.genesis, 2, legal_text: "right\n")

    repair =
      ChainFixture.successor(left, 3,
        legal_text: "repair\n",
        claims: %{"supersedes" => [left.digest, right.digest]}
      )

    revisions = [setup.genesis, left, right, repair]
    acceptances = Enum.flat_map(revisions, &ChainFixture.dual_acceptances(&1, setup))

    assert {:ok, %ChainFacts{chain_topology: :linear} = facts} =
             Chain.verify(
               Enum.map(revisions, & &1.bytes),
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    assert {:ok, repair.digest} ==
             Chain.governing_revision(facts, at!("2026-08-25T12:00:02Z"))
  end

  test "termination closes the charter without reactivating an older revision" do
    setup = ChainFixture.base()
    revision_2 = ChainFixture.successor(setup.genesis, 2)
    revisions = [setup.genesis, revision_2]
    acceptances = Enum.flat_map(revisions, &ChainFixture.dual_acceptances(&1, setup))

    termination =
      ChainFixture.termination(revision_2, setup.issuer, "issuer", %{
        "effective_at" => "2026-08-26T13:00:00Z"
      })

    assert {:ok, facts} =
             Chain.verify(
               Enum.map(revisions, & &1.bytes),
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [termination.compact],
               Limits.default()
             )

    assert {:ok, revision_2.digest} ==
             Chain.governing_revision(facts, at!("2026-08-26T12:59:59Z"))

    assert {:ok, :none} =
             Chain.governing_revision(facts, at!("2026-08-26T13:00:00Z"))
  end

  test "rejects missing predecessor bindings and invalid supersession targets" do
    setup = ChainFixture.base()
    zero = "sha-256:" <> String.duplicate("A", 43)

    bad_previous =
      ChainFixture.successor(setup.genesis, 2, claims: %{"prev_revision_digest" => zero})

    bad_supersession =
      ChainFixture.successor(setup.genesis, 2, claims: %{"supersedes" => [zero]})

    for revision <- [bad_previous, bad_supersession] do
      acceptances =
        ChainFixture.dual_acceptances(setup.genesis, setup) ++
          ChainFixture.dual_acceptances(revision, setup)

      assert {:error, %Error{code: :chain_invalid}} =
               Chain.verify(
                 [setup.genesis.bytes, revision.bytes],
                 Enum.map(acceptances, & &1.compact),
                 ChainFixture.descriptors(setup),
                 [],
                 Limits.default()
               )
    end
  end

  test "builds typed sets, forces the facts floor, and keeps public entry points total" do
    setup = ChainFixture.base()

    assert {:ok, %ArtifactSet{} = set} =
             CharterAgreementProtocol.build_set(
               [setup.genesis.bytes],
               [],
               [],
               ChainFixture.descriptors(setup)
             )

    assert set.revisions == [setup.genesis.bytes]
    assert {:ok, built} = Facts.build(ChainFacts, %{accepted_revision_digests: []}, [:custom])
    assert built.not_verified == @not_verified ++ [:custom]

    assert {:error, %Error{code: :invalid_type}} =
             CharterAgreementProtocol.build_set(:bad, [], [], [])

    assert {:error, %Error{code: :invalid_type}} =
             Chain.verify(:bad, [], [], [], Limits.default())

    assert {:error, %Error{code: :invalid_type}} =
             Chain.governing_revision(%{}, at!("2026-08-25T12:00:00Z"))
  end

  test "facts construction is closed, unions the floor, and redacts every facts record" do
    assert Facts.not_verified_floor() == @not_verified

    for module <- [
          AcceptanceFacts,
          ChainFacts,
          DescriptorFacts,
          ForkEvidence,
          RevisionFacts,
          TerminationFacts
        ] do
      attrs = module |> struct() |> Map.from_struct() |> Map.put(:not_verified, [:ignored])
      assert {:ok, value} = Facts.build(module, attrs)
      assert value.not_verified == @not_verified
      assert inspect(value) == "##{inspect(module)}<redacted>"
    end

    assert {:error, %Error{code: :invalid_type}} = Facts.build(ChainFacts, %{unknown: true})
    assert {:error, %Error{code: :invalid_type}} = Facts.build(ChainFacts, %{}, ["not-an-atom"])
    assert {:error, %Error{code: :invalid_type}} = Facts.build(Map, %{})
    assert {:error, %Error{code: :invalid_type}} = Facts.build(ChainFacts, [:not_keyword])
    assert {:error, %Error{code: :invalid_type}} = Facts.build(ChainFacts, :not_attributes)
  end

  test "raw artifact sets reject non-binary members" do
    assert {:error, %Error{code: :invalid_type}} = ArtifactSet.build([:not_bytes], [], [], [])
  end

  test "set verification rejects invalid limits, collection shapes, and collection bounds" do
    setup = ChainFixture.base()
    invalid_limits = %{Limits.default() | max_bytes: -1}
    zero_items = %{Limits.default() | max_artifact_set_items: 0}

    assert {:error, %Error{code: :invalid_limits}} = Chain.verify([], [], [], [], invalid_limits)

    assert {:error, %Error{code: :invalid_limits}} =
             Chain.verify(:bad, [], [], [], invalid_limits)

    assert {:error, %Error{code: :invalid_type}} = Chain.verify([], [], [], [], :not_limits)

    assert {:error, %Error{code: :limit_exceeded}} =
             Chain.verify([setup.genesis.bytes], [], [], [], zero_items)

    assert {:error, %Error{code: :invalid_type}} =
             Chain.verify([:not_bytes], [], [], [], Limits.default())

    assert_chain_error([], [], [], [])
    assert_chain_error([], [], ChainFixture.descriptors(setup), [])
    assert_chain_error([setup.genesis.bytes], [], [setup.issuer.compact], [])
  end

  test "set verification propagates descriptor decoding and chain verification failures" do
    setup = ChainFixture.base()

    assert {:error, %Error{code: :compact_invalid}} =
             Chain.verify([setup.genesis.bytes], [], ["bad"], [], Limits.default())

    invalid_successor =
      DescriptorFixture.successor(setup.issuer, 2, signing_private: setup.acceptor.private)

    assert {:error, %Error{code: :descriptor_chain_invalid}} =
             Chain.verify(
               [setup.genesis.bytes],
               [],
               [setup.issuer.compact, invalid_successor.compact, setup.acceptor.compact],
               [],
               Limits.default()
             )
  end

  test "set verification rejects malformed, duplicate, and cross-charter revision sets" do
    setup = ChainFixture.base()

    assert {:error, %Error{code: :invalid_syntax}} =
             Chain.verify(
               ["bad"],
               [],
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    assert_chain_error(
      [setup.genesis.bytes, setup.genesis.bytes],
      [],
      ChainFixture.descriptors(setup),
      []
    )

    other_root = CharterRevisionFixture.genesis(legal_text: "other charter\n")

    assert_chain_error(
      [setup.genesis.bytes, other_root.bytes],
      [],
      ChainFixture.descriptors(setup),
      []
    )

    wrong_charter =
      ChainFixture.successor(setup.genesis, 2, claims: %{"charter_id" => other_root.digest})

    assert_chain_error(
      [setup.genesis.bytes, wrong_charter.bytes],
      [],
      ChainFixture.descriptors(setup),
      []
    )

    orphan = ChainFixture.successor(setup.genesis, 2)

    assert_chain_error(
      [orphan.bytes],
      [],
      ChainFixture.descriptors(setup),
      []
    )
  end

  test "set verification rejects unroutable and invalid acceptance artifacts" do
    setup = ChainFixture.base()
    claims = AcceptanceFixture.claims(setup.genesis, setup.issuer, "issuer")

    wrong_type =
      claims
      |> Map.put("revision_digest", 1)
      |> AcceptanceFixture.compact(setup.issuer)

    missing_revision =
      claims
      |> Map.put("revision_digest", "sha-256:" <> String.duplicate("A", 43))
      |> AcceptanceFixture.compact(setup.issuer)

    wrong_signature =
      claims
      |> AcceptanceFixture.compact(setup.issuer, private: setup.acceptor.private)

    for compact <- [wrong_type.compact, missing_revision.compact] do
      assert_chain_error(
        [setup.genesis.bytes],
        [compact],
        ChainFixture.descriptors(setup),
        []
      )
    end

    assert {:error, %Error{code: :signature_invalid}} =
             Chain.verify(
               [setup.genesis.bytes],
               [wrong_signature.compact],
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    valid = ChainFixture.acceptance(setup.genesis, setup.issuer, "issuer")

    assert_chain_error(
      [setup.genesis.bytes],
      [valid.compact, valid.compact],
      ChainFixture.descriptors(setup),
      []
    )

    assert {:error, %Error{code: :compact_invalid}} =
             Chain.verify(
               [setup.genesis.bytes],
               ["bad"],
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )
  end

  test "set verification rejects unroutable and invalid termination artifacts" do
    setup = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)
    claims = TerminationFixture.claims(setup.genesis, setup.issuer, "issuer")

    wrong_type =
      claims
      |> Map.put("governing_revision_digest", 1)
      |> TerminationFixture.compact(setup.issuer)

    missing_descriptor =
      claims
      |> Map.put("party_descriptor_digest", "sha-256:" <> String.duplicate("A", 43))
      |> TerminationFixture.compact(setup.issuer)

    wrong_signature = TerminationFixture.compact(claims, setup.acceptor)

    for compact <- [wrong_type.compact, missing_descriptor.compact] do
      assert_chain_error(
        [setup.genesis.bytes],
        Enum.map(acceptances, & &1.compact),
        ChainFixture.descriptors(setup),
        [compact]
      )
    end

    assert {:error, %Error{code: :termination_invalid}} =
             Chain.verify(
               [setup.genesis.bytes],
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [wrong_signature.compact],
               Limits.default()
             )
  end

  test "accepted supersession requires every target to be bilaterally accepted" do
    setup = ChainFixture.base()
    left = ChainFixture.successor(setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(setup.genesis, 2, legal_text: "right\n")

    repair =
      ChainFixture.successor(left, 3, claims: %{"supersedes" => [left.digest, right.digest]})

    acceptances =
      [setup.genesis, left, repair]
      |> Enum.flat_map(&ChainFixture.dual_acceptances(&1, setup))

    assert_chain_error(
      Enum.map([setup.genesis, left, right, repair], & &1.bytes),
      Enum.map(acceptances, & &1.compact),
      ChainFixture.descriptors(setup),
      []
    )
  end

  test "uneven accepted branches remain contested without a common head" do
    setup = ChainFixture.base()
    left = ChainFixture.successor(setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(setup.genesis, 2, legal_text: "right\n")
    right_3 = ChainFixture.successor(right, 3)
    revisions = [setup.genesis, left, right, right_3]
    acceptances = Enum.flat_map(revisions, &ChainFixture.dual_acceptances(&1, setup))

    assert {:ok, facts} =
             Chain.verify(
               Enum.map(revisions, & &1.bytes),
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [],
               Limits.default()
             )

    assert facts.chain_topology == :forked
    assert {:ok, :contested} = Chain.governing_revision(facts, at!("2026-08-25T12:00:02Z"))
  end

  test "governing computation rejects a non-UTC DateTime" do
    {:ok, facts} = Facts.build(ChainFacts, %{})
    non_utc = %{at!("2026-08-25T12:00:00Z") | time_zone: "Europe/Paris"}

    assert {:error, %Error{code: :governing_invalid}} =
             Chain.governing_revision(facts, non_utc)
  end

  defp assert_chain_error(revisions, acceptances, descriptors, terminations) do
    assert {:error, %Error{code: :chain_invalid}} =
             Chain.verify(revisions, acceptances, descriptors, terminations, Limits.default())
  end

  defp at!(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    datetime
  end
end
