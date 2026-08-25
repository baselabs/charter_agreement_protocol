defmodule CharterAgreementProtocol.SigningInputTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    Acceptance,
    AcceptanceFixture,
    ArtifactSet,
    Base64Url,
    Canonicalization,
    ChainFixture,
    DescriptorFixture,
    Error,
    Limits,
    Receipt,
    ReceiptFixture,
    SigningInput,
    TerminationFixture,
    TerminationNotice
  }

  test "descriptor and receipt seams produce exact inputs and assemble external signatures" do
    descriptor = DescriptorFixture.genesis()

    assert {:ok, %SigningInput{kind: :party_descriptor} = descriptor_input} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => descriptor.kid,
               "claims" => descriptor.claims
             })

    assert descriptor_input.message ==
             descriptor_input.protected_segment <> "." <> descriptor_input.payload_segment

    descriptor_signature = sign(descriptor_input, descriptor.signing_private)

    assert {:ok, descriptor_compact} =
             CharterAgreementProtocol.assemble_compact(
               descriptor_input,
               descriptor_signature
             )

    assert {:ok, _facts} =
             CharterAgreementProtocol.verify_descriptor(
               descriptor_compact,
               nil,
               Limits.default()
             )

    setup = ChainFixture.base()

    chain =
      verified_chain(setup, [setup.genesis], ChainFixture.dual_acceptances(setup.genesis, setup))

    receipt_claims = ReceiptFixture.claims(setup.genesis)

    assert {:ok, %SigningInput{kind: :receipt} = receipt_input} =
             CharterAgreementProtocol.receipt_signing_input(%{
               "kid" => setup.issuer.kid,
               "claims" => receipt_claims
             })

    assert {:ok, receipt_compact} =
             CharterAgreementProtocol.assemble_compact(
               receipt_input,
               sign(receipt_input, setup.issuer.private)
             )

    assert {:ok, _facts} =
             CharterAgreementProtocol.verify_receipt(receipt_compact, chain, Limits.default())
  end

  test "acceptance and termination seams compose with verification",
    do: acceptance_and_termination()

  test "claims-truth refuses acceptance coordinates unequal to the retained revision" do
    setup = ChainFixture.base()
    {:ok, set} = raw_set(setup, [setup.genesis], [], [])

    false_claims =
      AcceptanceFixture.claims(setup.genesis, setup.issuer, "issuer", %{
        "revision_digest" =>
          CharterAgreementProtocol.CharterRevisionFixture.tagged(
            :charter_revision_content,
            "not-retained"
          )
      })

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, false_claims),
               set
             )
  end

  test "no-equivocation refuses an acceptance at a number occupied by another digest" do
    setup = ChainFixture.base()
    left = ChainFixture.successor(setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(setup.genesis, 2, legal_text: "right\n")
    right_acceptance = ChainFixture.acceptance(right, setup.issuer, "issuer")
    {:ok, set} = raw_set(setup, [setup.genesis, left, right], [right_acceptance], [])

    claims = AcceptanceFixture.claims(left, setup.issuer, "issuer")

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, claims),
               set
             )
  end

  test "ancestry-closed refuses a branch that excludes the dual-accepted head" do
    setup = ChainFixture.base()
    accepted_head = ChainFixture.successor(setup.genesis, 2, legal_text: "accepted\n")
    stale_parent = ChainFixture.successor(setup.genesis, 2, legal_text: "stale\n")
    stale_candidate = ChainFixture.successor(stale_parent, 3, legal_text: "stale child\n")

    acceptances =
      ChainFixture.dual_acceptances(setup.genesis, setup) ++
        ChainFixture.dual_acceptances(accepted_head, setup)

    {:ok, set} =
      raw_set(
        setup,
        [setup.genesis, accepted_head, stale_parent, stale_candidate],
        acceptances,
        []
      )

    claims = AcceptanceFixture.claims(stale_candidate, setup.issuer, "issuer")

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, claims),
               set
             )
  end

  test "ancestry coverage permits the bilateral supersession repair of accepted siblings" do
    setup = ChainFixture.base()
    left = ChainFixture.successor(setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(setup.genesis, 2, legal_text: "right\n")

    repair =
      ChainFixture.successor(left, 3,
        legal_text: "repair\n",
        claims: %{"supersedes" => [left.digest, right.digest]}
      )

    revisions = [setup.genesis, left, right, repair]

    acceptances =
      [setup.genesis, left, right]
      |> Enum.flat_map(&ChainFixture.dual_acceptances(&1, setup))

    {:ok, set} = raw_set(setup, revisions, acceptances, [])
    claims = AcceptanceFixture.claims(repair, setup.issuer, "issuer")

    assert {:ok, %SigningInput{kind: :acceptance}} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, claims),
               set
             )
  end

  test "assembly rejects forged inputs, wrong signatures, and key-shaped arguments" do
    descriptor = DescriptorFixture.genesis()

    assert {:ok, input} =
             CharterAgreementProtocol.descriptor_signing_input(
               envelope(descriptor.kid, descriptor.claims)
             )

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.assemble_compact(%{input | message: "forged"}, <<0::512>>)

    {:ok, empty_payload} = Canonicalization.encode({:object, []})
    empty_segment = Base64Url.encode(empty_payload)

    invalid_payload_input = %{
      input
      | payload_segment: empty_segment,
        message: input.protected_segment <> "." <> empty_segment
    }

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.assemble_compact(invalid_payload_input, <<0::512>>)

    assert {:error, %Error{code: :signature_invalid}} =
             CharterAgreementProtocol.assemble_compact(input, <<0::504>>)

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => descriptor.kid,
               "claims" => descriptor.claims,
               "signer" => fn _message -> <<0::512>> end
             })

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.assemble_compact(input, %{private: descriptor.private})
  end

  test "producer inputs are closed and total across invalid scalar, nesting, kid, and set shapes" do
    setup = ChainFixture.base()
    {:ok, set} = raw_set(setup, [setup.genesis], [], [])

    invalid_inputs = [
      %{"kid" => "", "claims" => setup.issuer.claims},
      %{"kid" => "bad kid", "claims" => setup.issuer.claims},
      %{"kid" => setup.issuer.kid, "claims" => %{atom_key: "bad"}},
      %{"kid" => setup.issuer.kid, "claims" => %{"nested" => [fn -> :bad end]}},
      %{"kid" => setup.issuer.kid, "claims" => %{"flag" => true, "missing" => nil}},
      %{"kid" => setup.issuer.kid, "claims" => %{"bad" => fn -> :bad end}}
    ]

    for input <- invalid_inputs do
      assert {:error, %Error{code: :signing_input_invalid}} =
               CharterAgreementProtocol.descriptor_signing_input(input)
    end

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.acceptance_signing_input(
               %{"kid" => "", "claims" => %{}},
               set
             )

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.acceptance_signing_input(%{}, :not_a_set)

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.termination_signing_input(
               %{"kid" => "", "claims" => %{}},
               set
             )

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.termination_signing_input(%{}, :not_a_set)
  end

  test "artifact signing decoders remain total at their package-internal boundary" do
    limits = Limits.default()
    invalid_limits = %{limits | max_bytes: -1}

    for module <- [Acceptance, Receipt, TerminationNotice] do
      assert {:error, %Error{code: :invalid_type}} = module.decode_for_signing(:bad, limits)

      assert {:error, %Error{code: :invalid_limits}} =
               module.decode_for_signing(:bad, invalid_limits)

      assert {:error, %Error{code: :invalid_type}} = module.decode_for_signing(:bad, :bad)
    end
  end

  test "set guards refuse wrong roles, missing revisions, stale termination, and contested numbers" do
    setup = ChainFixture.base()
    {:ok, genesis_set} = raw_set(setup, [setup.genesis], [], [])

    wrong_party =
      AcceptanceFixture.claims(setup.genesis, setup.issuer, "issuer", %{
        "party_descriptor_digest" => setup.acceptor.digest
      })

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, wrong_party),
               genesis_set
             )

    missing_revision =
      TerminationFixture.claims(setup.genesis, setup.issuer, "issuer", %{
        "governing_revision_digest" =>
          CharterAgreementProtocol.CharterRevisionFixture.tagged(
            :charter_revision_content,
            "missing"
          )
      })

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, missing_revision),
               genesis_set
             )

    unlisted_reason =
      TerminationFixture.claims(setup.genesis, setup.issuer, "issuer", %{
        "reason_code" => "not-in-charter"
      })

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, unlisted_reason),
               genesis_set
             )

    revision_2 = ChainFixture.successor(setup.genesis, 2)

    accepted =
      ChainFixture.dual_acceptances(setup.genesis, setup) ++
        ChainFixture.dual_acceptances(revision_2, setup)

    {:ok, advanced_set} = raw_set(setup, [setup.genesis, revision_2], accepted, [])
    stale_termination = TerminationFixture.claims(setup.genesis, setup.issuer, "issuer")

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, stale_termination),
               advanced_set
             )

    left = ChainFixture.successor(setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(setup.genesis, 2, legal_text: "right\n")

    fork_acceptances =
      Enum.flat_map([setup.genesis, left, right], &ChainFixture.dual_acceptances(&1, setup))

    {:ok, fork_set} = raw_set(setup, [setup.genesis, left, right], fork_acceptances, [])
    contested_termination = TerminationFixture.claims(left, setup.issuer, "issuer")

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, contested_termination),
               fork_set
             )
  end

  defp acceptance_and_termination do
    setup = ChainFixture.base()
    {:ok, unsigned_set} = raw_set(setup, [setup.genesis], [], [])
    acceptance_claims = AcceptanceFixture.claims(setup.genesis, setup.issuer, "issuer")

    assert {:ok, %SigningInput{kind: :acceptance} = acceptance_input} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, acceptance_claims),
               unsigned_set
             )

    assert {:ok, acceptance_compact} =
             CharterAgreementProtocol.assemble_compact(
               acceptance_input,
               sign(acceptance_input, setup.issuer.private)
             )

    {:ok, descriptor_chain} =
      CharterAgreementProtocol.DescriptorChain.verify(
        [setup.issuer.compact],
        Limits.default()
      )

    {:ok, revision} =
      CharterAgreementProtocol.CharterRevision.decode(setup.genesis.bytes, Limits.default())

    assert {:ok, _facts} =
             CharterAgreementProtocol.verify_acceptance(
               acceptance_compact,
               revision,
               descriptor_chain,
               Limits.default()
             )

    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)
    {:ok, accepted_set} = raw_set(setup, [setup.genesis], acceptances, [])

    termination_claims =
      TerminationFixture.claims(setup.genesis, setup.issuer, "issuer")

    assert {:ok, %SigningInput{kind: :termination} = termination_input} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, termination_claims),
               accepted_set
             )

    assert {:ok, termination_compact} =
             CharterAgreementProtocol.assemble_compact(
               termination_input,
               sign(termination_input, setup.issuer.private)
             )

    assert {:ok, _facts} =
             CharterAgreementProtocol.verify_termination(
               termination_compact,
               revision,
               descriptor_chain,
               Limits.default()
             )
  end

  defp verified_chain(setup, revisions, acceptances) do
    {:ok, chain} =
      CharterAgreementProtocol.verify_chain(
        Enum.map(revisions, & &1.bytes),
        Enum.map(acceptances, & &1.compact),
        ChainFixture.descriptors(setup),
        [],
        Limits.default()
      )

    chain
  end

  defp raw_set(setup, revisions, acceptances, terminations) do
    ArtifactSet.build(
      Enum.map(revisions, & &1.bytes),
      Enum.map(acceptances, & &1.compact),
      Enum.map(terminations, & &1.compact),
      ChainFixture.descriptors(setup)
    )
  end

  defp envelope(kid, claims), do: %{"kid" => kid, "claims" => claims}

  defp sign(input, private_key),
    do: :crypto.sign(:eddsa, :none, input.message, [private_key, :ed25519])
end
