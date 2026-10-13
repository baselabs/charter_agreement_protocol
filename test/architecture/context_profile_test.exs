defmodule CharterAgreementProtocol.Architecture.ContextProfileTest do
  @moduledoc false
  use ExUnit.Case, async: true

  # A caller's profile reaches every artifact a standalone verify call
  # re-verifies: the supplied revision, the supplied descriptor history and
  # the artifact itself. A narrowed profile must never pass a call whose
  # context it excludes.

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    AcceptanceFixture,
    Capability.Profile,
    Chain,
    CharterRevision,
    CharterRevisionFixture,
    DescriptorChain,
    DescriptorFixture,
    Error,
    Limits,
    ReceiptFacts,
    ReceiptFixture,
    TerminationFacts,
    TerminationFixture
  }

  @in_profile [
    descriptor_revision: 2,
    descriptor_alg: "Ed25519",
    revision_revision: 2,
    artifact_revision: 2,
    artifact_alg: "Ed25519"
  ]

  setup do
    {:ok, narrow} = Profile.new(algorithms: ["Ed25519"], revisions: {2, 2})
    {:ok, revisions_only} = Profile.new(revisions: {2, 2})
    %{narrow: narrow, revisions_only: revisions_only}
  end

  test "an in-profile context passes every standalone call", %{narrow: narrow} do
    world = world(@in_profile)

    assert {:ok, %AcceptanceFacts{}} = acceptance(world, narrow)
    assert {:ok, %TerminationFacts{}} = termination(world, narrow)
    assert {:ok, %ReceiptFacts{}} = receipt_on_revision(world, narrow)
    assert {:ok, %ReceiptFacts{}} = receipt_on_chain(world, narrow)
  end

  test "an out-of-profile descriptor algorithm fails the calls that re-verify it",
       %{narrow: narrow} do
    world = world(Keyword.put(@in_profile, :descriptor_alg, "EdDSA"))

    assert {:error, %Error{code: :algorithm_outside_profile}} = acceptance(world, narrow)
    assert {:error, %Error{code: :algorithm_outside_profile}} = termination(world, narrow)
    assert {:error, %Error{code: :algorithm_outside_profile}} = receipt_on_chain(world, narrow)
    assert {:ok, %ReceiptFacts{}} = receipt_on_revision(world, narrow)
  end

  test "an out-of-profile descriptor revision fails the calls that re-verify it",
       %{revisions_only: revisions_only} do
    world =
      world(Keyword.merge(@in_profile, descriptor_revision: 1, descriptor_alg: "EdDSA"))

    assert {:error, %Error{code: :revision_outside_profile}} =
             acceptance(world, revisions_only)

    assert {:error, %Error{code: :revision_outside_profile}} =
             termination(world, revisions_only)

    assert {:error, %Error{code: :revision_outside_profile}} =
             receipt_on_chain(world, revisions_only)
  end

  test "an out-of-profile charter revision fails every call that re-verifies it",
       %{narrow: narrow} do
    world = world(Keyword.put(@in_profile, :revision_revision, 1))

    assert {:error, %Error{code: :revision_outside_profile}} = acceptance(world, narrow)
    assert {:error, %Error{code: :revision_outside_profile}} = termination(world, narrow)

    assert {:error, %Error{code: :revision_outside_profile}} =
             receipt_on_revision(world, narrow)

    assert {:error, %Error{code: :revision_outside_profile}} = receipt_on_chain(world, narrow)
  end

  test "a revision-only receipt outside the profile fails on either axis", %{narrow: narrow} do
    by_alg = world(Keyword.put(@in_profile, :artifact_alg, "EdDSA"))
    by_revision = world(Keyword.put(@in_profile, :artifact_revision, 3))

    assert {:error, %Error{code: :algorithm_outside_profile}} =
             receipt_on_revision(by_alg, narrow)

    assert {:error, %Error{code: :revision_outside_profile}} =
             receipt_on_revision(by_revision, narrow)
  end

  test "a malformed revision outranks a profile rejection in a chain view, in either position",
       %{narrow: narrow} do
    world = world(Keyword.put(@in_profile, :revision_revision, 1))
    {:error, %Error{code: malformed}} = CharterRevision.decode("{}", Limits.default())
    refute malformed == :revision_outside_profile

    for revisions <- [[world.revision_bytes, "{}"], ["{}", world.revision_bytes]] do
      assert {:error, %Error{code: ^malformed}} =
               Chain.verify(
                 revisions,
                 world.acceptance_compacts,
                 world.descriptor_compacts,
                 [],
                 Limits.default(),
                 narrow
               )
    end
  end

  test "the full profile keeps every out-of-profile world verifying" do
    for overrides <- [
          [descriptor_alg: "EdDSA"],
          [descriptor_revision: 1, descriptor_alg: "EdDSA"],
          [revision_revision: 1],
          [artifact_alg: "EdDSA"]
        ] do
      world = world(Keyword.merge(@in_profile, overrides))
      full = Profile.full()

      assert {:ok, %AcceptanceFacts{}} = acceptance(world, full)
      assert {:ok, %TerminationFacts{}} = termination(world, full)
      assert {:ok, %ReceiptFacts{}} = receipt_on_revision(world, full)
      assert {:ok, %ReceiptFacts{}} = receipt_on_chain(world, full)
    end
  end

  defp acceptance(world, profile) do
    CharterAgreementProtocol.verify_acceptance(
      world.issuer_acceptance.compact,
      world.revision,
      world.issuer_chain,
      Limits.default(),
      profile
    )
  end

  defp termination(world, profile) do
    CharterAgreementProtocol.verify_termination(
      world.termination.compact,
      world.revision,
      world.issuer_chain,
      Limits.default(),
      profile
    )
  end

  defp receipt_on_revision(world, profile) do
    CharterAgreementProtocol.verify_receipt(
      world.receipt,
      world.revision,
      Limits.default(),
      profile
    )
  end

  defp receipt_on_chain(world, profile) do
    CharterAgreementProtocol.verify_receipt(
      world.receipt,
      world.chain_facts,
      Limits.default(),
      profile
    )
  end

  defp world(options) do
    limits = Limits.default()
    artifact_revision = Keyword.fetch!(options, :artifact_revision)
    artifact_alg = Keyword.fetch!(options, :artifact_alg)
    issuer = descriptor(DescriptorFixture.key(1, "genesis-key"), options)
    acceptor = descriptor(DescriptorFixture.key(2, "acceptor-key"), options)

    revision_fixture =
      CharterRevisionFixture.genesis(
        claims: %{
          "protocol_revision" => Keyword.fetch!(options, :revision_revision),
          "parties" => [
            %{"party_descriptor_digest" => issuer.digest, "role" => "issuer"},
            %{"party_descriptor_digest" => acceptor.digest, "role" => "acceptor"}
          ]
        }
      )

    {:ok, revision} = CharterRevision.decode(revision_fixture.bytes, limits)
    {:ok, issuer_chain} = DescriptorChain.verify([issuer.compact], limits)

    signed = fn descriptor, role ->
      revision_fixture
      |> AcceptanceFixture.claims(descriptor, role, %{"protocol_revision" => artifact_revision})
      |> AcceptanceFixture.compact(descriptor, alg: artifact_alg)
    end

    issuer_acceptance = signed.(issuer, "issuer")
    acceptor_acceptance = signed.(acceptor, "acceptor")

    termination =
      revision_fixture
      |> TerminationFixture.claims(issuer, "issuer", %{"protocol_revision" => artifact_revision})
      |> TerminationFixture.compact(issuer, alg: artifact_alg)

    {:ok, chain_facts} =
      CharterAgreementProtocol.verify_chain(
        [revision_fixture.bytes],
        [issuer_acceptance.compact, acceptor_acceptance.compact],
        [issuer.compact, acceptor.compact],
        [],
        limits
      )

    receipt =
      revision_fixture
      |> ReceiptFixture.claims(%{"protocol_revision" => artifact_revision})
      |> ReceiptFixture.compact(issuer,
        protected: %{"alg" => artifact_alg, "typ" => "cap+receipt", "kid" => issuer.kid}
      )

    %{
      revision: revision,
      revision_bytes: revision_fixture.bytes,
      acceptance_compacts: [issuer_acceptance.compact, acceptor_acceptance.compact],
      descriptor_compacts: [issuer.compact, acceptor.compact],
      issuer_chain: issuer_chain,
      issuer_acceptance: issuer_acceptance,
      termination: termination,
      chain_facts: chain_facts,
      receipt: receipt
    }
  end

  defp descriptor({key, _private} = pair, options) do
    DescriptorFixture.genesis(
      key: pair,
      claims: %{"protocol_revision" => Keyword.fetch!(options, :descriptor_revision)},
      protected: %{
        "alg" => Keyword.fetch!(options, :descriptor_alg),
        "typ" => "cap+party",
        "kid" => key["key_id"]
      }
    )
  end
end
