defmodule CharterAgreementProtocol.ReleaseIdentitySurfaceTest do
  @moduledoc false
  # Coverage completion for the release-identity surfaces whose production
  # execution otherwise lives only in gate scripts (the recorder, the
  # release-candidate comparison, the historical differential harness) or in
  # corpus dispatch paths the certified cases do not reach.
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    Algorithm,
    Capability,
    Capability.Profile,
    Chain,
    ChainFixture,
    Conformance.Corpus,
    Conformance.Runner,
    DescriptorChain,
    Digest,
    Error,
    Limits,
    PartyDescriptor,
    ReceiptFixture,
    TerminationNotice
  }

  setup do
    setup = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)
    compacts = Enum.map(acceptances, & &1.compact)

    {:ok, chain} =
      Chain.verify(
        [setup.genesis.bytes],
        compacts,
        ChainFixture.descriptors(setup),
        [],
        Limits.default()
      )

    {:ok, descriptor_chain} =
      DescriptorChain.verify([hd(ChainFixture.descriptors(setup))], Limits.default())

    {:ok, revision} =
      CharterAgreementProtocol.CharterRevision.decode(setup.genesis.bytes, Limits.default())

    %{
      setup: setup,
      acceptances: acceptances,
      compacts: compacts,
      chain: chain,
      descriptor_chain: descriptor_chain,
      revision: revision
    }
  end

  test "the signature registry digest is a stable tagged identity over the rows" do
    digest = Algorithm.registry_digest() |> Digest.to_tagged()
    assert String.starts_with?(digest, "sha-256:")
    assert digest == Algorithm.registry_digest() |> Digest.to_tagged()
  end

  test "an unknown key algorithm never reports a known-answer verdict" do
    refute Capability.kat_verifies?("ML-DSA-99")
  end

  test "Profile.new with no arguments builds the full profile" do
    assert {:ok, profile} = Profile.new()
    assert profile == Profile.full()
  end

  test "the historical load mode accepts the shipped corpus and rejects tampered counts" do
    files =
      "priv/conformance/**/*"
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Map.new(&{Path.relative_to(&1, "priv/conformance"), File.read!(&1)})

    assert {:ok, corpus} = Corpus.load(files, true)
    assert corpus.cases != []

    # Any tampered byte in a historical index is corruption, not history:
    # the corpus self-digest fires before the count reconciliation can even
    # run — exactly the integrity property a frozen released artifact needs.
    tampered =
      Map.update!(files, "index.json", fn bytes ->
        String.replace(bytes, ~s("total_cases":104), ~s("total_cases":105))
      end)

    assert {:error, %Error{code: :corpus_index_invalid}} = Corpus.load(tampered, true)
  end

  test "the runner's profile spec helpers are total", %{setup: setup, acceptances: acceptances} do
    base_input = %{
      "revisions" => [setup.genesis.bytes],
      "acceptances" => Enum.map(acceptances, & &1.compact),
      "descriptors" => ChainFixture.descriptors(setup),
      "terminations" => []
    }

    revisions_only =
      case_body(base_input, %{"revisions" => %{"min" => 1, "max" => 1}})

    algorithms_only = case_body(base_input, %{"algorithms" => ["EdDSA"]})

    malformed_algorithm =
      case_body(base_input, %{"algorithms" => "EdDSA", "revisions" => %{"min" => 1, "max" => 1}})

    malformed_revisions =
      case_body(base_input, %{"algorithms" => ["EdDSA"], "revisions" => [1, 3]})

    for body <- [revisions_only, algorithms_only] do
      assert {:ok, %{"status" => "valid"}} = run_profile_case(body)
    end

    assert {:ok, %{"status" => "invalid", "error_code" => "invalid_type"}} =
             run_profile_case(malformed_algorithm)

    assert {:ok, %{"status" => "invalid", "error_code" => "invalid_type"}} =
             run_profile_case(malformed_revisions)
  end

  test "the facade exposes every profiled verify arity", %{
    setup: setup,
    compacts: compacts,
    descriptor_chain: descriptor_chain,
    revision: revision,
    chain: chain
  } do
    [issuer | _] = ChainFixture.descriptors(setup)
    {:ok, profile} = Profile.new(algorithms: ["EdDSA", "Ed25519"], revisions: {1, 3})

    cap = CharterAgreementProtocol

    assert {:ok, _} = cap.verify_descriptor(issuer, nil, Limits.default(), profile)
    assert {:ok, _} = cap.verify_descriptor_chain([issuer], Limits.default(), profile)

    [acceptance | _] = compacts

    assert {:ok, _} =
             cap.verify_acceptance(
               acceptance,
               revision,
               descriptor_chain,
               Limits.default(),
               profile
             )

    termination =
      ChainFixture.termination(setup.genesis, setup.issuer, "issuer")
      |> Map.get(:compact)

    assert {:ok, _} =
             cap.verify_termination(
               termination,
               revision,
               descriptor_chain,
               Limits.default(),
               profile
             )

    receipt_claims = ReceiptFixture.claims(setup.genesis)
    receipt_compact = ReceiptFixture.compact(receipt_claims, setup.issuer)
    assert {:ok, _} = cap.verify_receipt(receipt_compact, chain, Limits.default(), profile)

    assert {:ok, _} =
             cap.verify_chain(
               [setup.genesis.bytes],
               compacts,
               ChainFixture.descriptors(setup),
               [],
               Limits.default(),
               profile
             )
  end

  test "an out-of-profile CHILD descriptor surfaces its code through the chain aggregation" do
    import CharterAgreementProtocol.DescriptorFixture
    alias CharterAgreementProtocol.Error

    genesis_descriptor = genesis()
    successor_descriptor = successor(genesis_descriptor, 2, claims: %{"protocol_revision" => 2})
    {:ok, rev_one_profile} = Profile.new(revisions: {1, 1})

    assert {:error, %Error{code: :revision_outside_profile}} =
             DescriptorChain.verify(
               [genesis_descriptor.compact, successor_descriptor.compact],
               Limits.default(),
               rev_one_profile
             )
  end

  test "the catch-all type clauses are total across the profiled surfaces" do
    alias CharterAgreementProtocol.{Chain, CompactJws, Error, PartyDescriptor}

    assert {:error, %Error{code: :invalid_type}} =
             Chain.verify("not-a-list", [], [], [], Limits.default(), Profile.full())

    # the /5 type catch-all (non-limits fifth argument)
    assert {:error, %Error{code: :invalid_type}} = Chain.verify([], [], [], [], "limits")

    # the /6 full catch-all (non-limits, non-profile trailing arguments)
    assert {:error, %Error{code: :invalid_type}} =
             Chain.verify([], [], [], [], "limits", "profile")

    assert {:error, %Error{code: :signature_invalid}} =
             CompactJws.verify_signature(%{}, <<0>>, "Ed25519", Profile.full())

    assert {:error, %Error{code: :invalid_type}} =
             PartyDescriptor.verify("compact", nil, "limits", Profile.full())
  end

  test "the honest-halt branches are total and order-independent" do
    alias CharterAgreementProtocol.{Capability.Profile, DescriptorChain, Error, Limits}

    import CharterAgreementProtocol.DescriptorFixture

    # An Ed25519-framed rev-2 genesis with a default-framed (EdDSA) child:
    # under an Ed25519-only profile the CHILD is algorithm-outside and the
    # honest code must surface through the chain aggregation, deterministically.
    {genesis_key, genesis_private} = key(1, "genesis-key")

    genesis_claims = %{
      "protocol_revision" => 2,
      "descriptor_number" => 1,
      "verification_keys" => [genesis_key],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:00Z"
    }

    ed25519_genesis =
      compact(genesis_claims, "genesis-key", genesis_private,
        protected: %{"alg" => "Ed25519", "typ" => "cap+party", "kid" => "genesis-key"}
      )

    eddsa_child = successor(ed25519_genesis, 2, claims: %{"protocol_revision" => 2})
    {:ok, ed25519_only} = Profile.new(algorithms: ["Ed25519"], revisions: {1, 3})

    assert {:error, %Error{code: :algorithm_outside_profile}} =
             DescriptorChain.verify(
               [ed25519_genesis.compact, eddsa_child.compact],
               Limits.default(),
               ed25519_only
             )

    # the substrate branch is decided purely at the boundary
    assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
             CharterAgreementProtocol.PartyDescriptor.honest_halt(
               :algorithm_unsupported_on_substrate
             )
  end

  defp case_body(input, profile) do
    %{
      "id" => "profile-helper-probe",
      "surface" => "chain.verify_profile",
      "class" => "profile_narrow_valid",
      "input" => Map.put(input, "profile", profile),
      "expect" => %{
        "status" => "valid",
        "output" => %{"charter_id" => nil, "topology" => "linear"}
      }
    }
  end

  defp run_profile_case(case_body) do
    corpus =
      struct!(Corpus, %{
        cases: [case_body],
        index: %{},
        index_bytes: "",
        case_ids: MapSet.new([case_body["id"]]),
        identity: ""
      })

    [result] = Runner.run(corpus)
    actual = result.actual

    case actual do
      %{"status" => _} -> {:ok, actual}
      %{"error_code" => code} -> {:error, Error.new(String.to_atom(code), ["profile"])}
    end
  end
end
