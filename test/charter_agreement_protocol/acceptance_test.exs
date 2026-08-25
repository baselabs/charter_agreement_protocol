defmodule CharterAgreementProtocol.AcceptanceTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    Acceptance,
    AcceptanceFacts,
    AcceptanceFixture,
    CharterRevisionFixture,
    DescriptorFixture,
    Error,
    Limits
  }

  test "verifies one countersignature against exact revision and descriptor facts" do
    setup = setup_acceptance()

    assert {:ok, %AcceptanceFacts{} = facts} =
             CharterAgreementProtocol.verify_acceptance(
               setup.acceptance.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    assert facts.acceptance_digest == setup.acceptance.digest
    assert facts.charter_id == setup.revision_fixture.digest
    assert facts.revision_number == 1
    assert facts.revision_digest == setup.revision_fixture.digest
    assert facts.party_descriptor_digest == setup.issuer.digest
    assert facts.party_role == "issuer"
    assert facts.descriptor_position == :head
  end

  test "rejects every mismatched revision-chain and party-binding claim" do
    setup = setup_acceptance()
    zero = "sha-256:" <> String.duplicate("A", 43)

    variants = [
      %{"charter_id" => zero},
      %{"revision_number" => 2, "prev_revision_digest" => zero},
      %{"revision_digest" => zero},
      %{"prev_revision_digest" => zero},
      %{"party_descriptor_digest" => setup.acceptor.digest},
      %{"party_role" => "acceptor"}
    ]

    for overrides <- variants do
      claims = AcceptanceFixture.claims(setup.revision_fixture, setup.issuer, "issuer", overrides)
      acceptance = AcceptanceFixture.compact(claims, setup.issuer)

      assert {:error, %Error{}} =
               CharterAgreementProtocol.verify_acceptance(
                 acceptance.compact,
                 setup.revision,
                 setup.chain,
                 Limits.default()
               )
    end
  end

  test "rejects wrong signatures, wrong types, forged revisions, and forged descriptor facts" do
    setup = setup_acceptance()
    {_key, wrong_private} = DescriptorFixture.key(9, "wrong")

    wrong =
      setup.revision_fixture
      |> AcceptanceFixture.claims(setup.issuer, "issuer")
      |> AcceptanceFixture.compact(setup.issuer, private: wrong_private)

    assert {:error, %Error{code: :signature_invalid}} =
             CharterAgreementProtocol.verify_acceptance(
               wrong.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    unknown_kid =
      setup.revision_fixture
      |> AcceptanceFixture.claims(setup.issuer, "issuer")
      |> AcceptanceFixture.compact(setup.issuer, kid: "unknown-key")

    assert {:error, %Error{code: :acceptance_invalid}} =
             Acceptance.verify(
               unknown_kid.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    malformed_digest =
      setup.revision_fixture
      |> AcceptanceFixture.claims(setup.issuer, "issuer", %{
        "charter_id" => "sha-256:" <> String.duplicate("_", 43)
      })
      |> AcceptanceFixture.compact(setup.issuer)

    assert {:error, %Error{code: :acceptance_invalid}} =
             Acceptance.verify(
               malformed_digest.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    forged_revision = %{setup.revision | revision_number: 9}
    forged_chain = %{setup.chain | descriptors: []}

    assert {:ok, %AcceptanceFacts{revision_number: 1}} =
             Acceptance.verify(
               setup.acceptance.compact,
               forged_revision,
               setup.chain,
               Limits.default()
             )

    assert {:error, %Error{}} =
             Acceptance.verify(
               setup.acceptance.compact,
               setup.revision,
               forged_chain,
               Limits.default()
             )

    for descriptors <- [[1], :not_a_list] do
      malformed_chain = %{setup.chain | descriptors: descriptors}

      assert {:error, %Error{code: :descriptor_chain_invalid}} =
               Acceptance.verify(
                 setup.acceptance.compact,
                 setup.revision,
                 malformed_chain,
                 Limits.default()
               )
    end

    assert {:error, %Error{code: :invalid_type}} =
             Acceptance.verify(:not_bytes, setup.revision, setup.chain, Limits.default())

    assert {:error, %Error{code: :invalid_type}} =
             Acceptance.verify(setup.acceptance.compact, setup.revision, setup.chain, %{})

    invalid_limits = %{Limits.default() | max_bytes: -1}

    assert {:error, %Error{code: :invalid_limits}} =
             Acceptance.verify(
               setup.acceptance.compact,
               setup.revision,
               setup.chain,
               invalid_limits
             )

    assert {:error, %Error{code: :invalid_limits}} =
             Acceptance.verify(
               setup.acceptance.compact,
               :not_a_revision,
               setup.chain,
               invalid_limits
             )
  end

  test "retains superseded and contested descriptor positions without choosing freshness" do
    issuer = DescriptorFixture.genesis()
    successor = DescriptorFixture.successor(issuer, 2)
    sibling = DescriptorFixture.successor(issuer, 2, key: DescriptorFixture.key(3, "sibling"))
    acceptor = DescriptorFixture.genesis(key: DescriptorFixture.key(4, "acceptor-key"))

    for {compacts, expected} <- [
          {[issuer.compact, successor.compact], :superseded},
          {[issuer.compact, successor.compact, sibling.compact], :contested}
        ] do
      setup = setup_acceptance(issuer: issuer, acceptor: acceptor, compacts: compacts)

      assert {:ok, %AcceptanceFacts{descriptor_position: ^expected}} =
               Acceptance.verify(
                 setup.acceptance.compact,
                 setup.revision,
                 setup.chain,
                 Limits.default()
               )
    end
  end

  test "same signer at one charter number over different revisions proves equivocation" do
    setup = setup_acceptance()

    successor_a =
      CharterRevisionFixture.successor(setup.revision_fixture, 2,
        claims: %{"parties" => setup.revision_fixture.claims["parties"]}
      )

    successor_b =
      CharterRevisionFixture.successor(setup.revision_fixture, 2,
        legal_text: "different terms\n",
        claims: %{"parties" => setup.revision_fixture.claims["parties"]}
      )

    facts =
      for revision_fixture <- [successor_a, successor_b] do
        {:ok, revision} =
          CharterAgreementProtocol.decode_charter_revision(
            revision_fixture.bytes,
            Limits.default()
          )

        acceptance =
          revision_fixture
          |> AcceptanceFixture.claims(setup.issuer, "issuer")
          |> AcceptanceFixture.compact(setup.issuer)

        {:ok, facts} =
          Acceptance.verify(acceptance.compact, revision, setup.chain, Limits.default())

        facts
      end

    assert {:ok, evidence} = Acceptance.equivocation(Enum.at(facts, 0), Enum.at(facts, 1))
    assert evidence.kind == :acceptance_equivocation
    assert evidence.revision_number == 2
    assert length(evidence.revision_digests) == 2
    assert evidence.winner == nil

    assert {:error, %Error{code: :acceptance_equivocation_invalid}} =
             Acceptance.equivocation(Enum.at(facts, 0), Enum.at(facts, 0))

    assert {:error, %Error{code: :acceptance_equivocation_invalid}} =
             Acceptance.equivocation(:not_facts, Enum.at(facts, 0))
  end

  defp setup_acceptance(options \\ []) do
    issuer = Keyword.get_lazy(options, :issuer, &DescriptorFixture.genesis/0)

    acceptor =
      Keyword.get_lazy(options, :acceptor, fn ->
        DescriptorFixture.genesis(key: DescriptorFixture.key(2, "acceptor-key"))
      end)

    revision_fixture =
      CharterRevisionFixture.genesis(
        claims: %{
          "parties" => [
            %{"party_descriptor_digest" => issuer.digest, "role" => "issuer"},
            %{"party_descriptor_digest" => acceptor.digest, "role" => "acceptor"}
          ]
        }
      )

    {:ok, revision} =
      CharterAgreementProtocol.decode_charter_revision(revision_fixture.bytes, Limits.default())

    compacts = Keyword.get(options, :compacts, [issuer.compact])
    {:ok, chain} = CharterAgreementProtocol.verify_descriptor_chain(compacts, Limits.default())

    acceptance =
      revision_fixture
      |> AcceptanceFixture.claims(issuer, "issuer")
      |> AcceptanceFixture.compact(issuer)

    %{
      issuer: issuer,
      acceptor: acceptor,
      revision_fixture: revision_fixture,
      revision: revision,
      chain: chain,
      acceptance: acceptance
    }
  end
end
