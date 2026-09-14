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
               "claims" => mint(descriptor.claims)
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
               "claims" => mint(receipt_claims)
             })

    assert {:ok, receipt_compact} =
             CharterAgreementProtocol.assemble_compact(
               receipt_input,
               sign(receipt_input, setup.issuer.private)
             )

    assert {:ok, _facts} =
             CharterAgreementProtocol.verify_receipt(receipt_compact, chain, Limits.default())
  end

  test "descriptor signing retains protocol-valid floating extension values" do
    descriptor =
      DescriptorFixture.genesis(
        claims: %{
          "extensions" => %{
            "critical" => %{},
            "optional" => %{
              "com.example/observation" => %{"observed_price" => 1.5}
            }
          }
        }
      )

    assert {:ok, _facts} =
             CharterAgreementProtocol.verify_descriptor(
               descriptor.compact,
               nil,
               Limits.default()
             )

    assert {:ok, %SigningInput{kind: :party_descriptor}} =
             CharterAgreementProtocol.descriptor_signing_input(
               envelope(descriptor.kid, descriptor.claims)
             )
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

  test "ancestry coverage accepts a successor of the retained accepted head" do
    setup = ChainFixture.base()
    candidate = ChainFixture.successor(setup.genesis, 2)
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)
    {:ok, set} = raw_set(setup, [setup.genesis, candidate], acceptances, [])
    claims = AcceptanceFixture.claims(candidate, setup.issuer, "issuer")

    assert {:ok, %SigningInput{kind: :acceptance}} =
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

  test "termination framing requires the claimed revision to govern at effective_at" do
    setup = ChainFixture.base()
    proposal = ChainFixture.successor(setup.genesis, 2)
    genesis_acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)

    {:ok, proposed_set} =
      raw_set(setup, [setup.genesis, proposal], genesis_acceptances, [])

    proposed_claims = TerminationFixture.claims(proposal, setup.issuer, "issuer")

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, proposed_claims),
               proposed_set
             )

    future =
      ChainFixture.successor(setup.genesis, 2,
        claims: %{"effective_from" => "2026-08-27T00:00:00Z"}
      )

    all_acceptances = genesis_acceptances ++ ChainFixture.dual_acceptances(future, setup)
    {:ok, future_set} = raw_set(setup, [setup.genesis, future], all_acceptances, [])

    governing_claims =
      TerminationFixture.claims(setup.genesis, setup.issuer, "issuer", %{
        "effective_at" => "2026-08-26T13:00:00Z"
      })

    assert {:ok, %SigningInput{kind: :termination}} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, governing_claims),
               future_set
             )
  end

  test "set verification errors remain typed instead of becoming signer refusals" do
    setup = ChainFixture.base()

    {:ok, malformed_set} =
      ArtifactSet.build(
        [setup.genesis.bytes],
        ["not-a-compact-jws"],
        [],
        ChainFixture.descriptors(setup)
      )

    claims = AcceptanceFixture.claims(setup.genesis, setup.issuer, "issuer")

    assert {:error, %Error{code: :compact_invalid}} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, claims),
               malformed_set
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

  test "the producer input shape fails closed on malformed claims and kids" do
    descriptor = DescriptorFixture.genesis()

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => descriptor.kid,
               "claims" => Map.put(mint(descriptor.claims), :atom_key, 1)
             })

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => "",
               "claims" => mint(descriptor.claims)
             })

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => 5,
               "claims" => mint(descriptor.claims)
             })

    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => "bad kid!",
               "claims" => mint(descriptor.claims)
             })
  end

  test "set-aware producers refuse coordinates the verified set cannot resolve" do
    setup = ChainFixture.base()
    {:ok, genesis_set} = raw_set(setup, [setup.genesis], [], [])

    missing_digest =
      CharterAgreementProtocol.CharterRevisionFixture.tagged(
        :charter_revision_content,
        "not-in-set"
      )

    missing_acceptance =
      AcceptanceFixture.claims(setup.genesis, setup.issuer, "issuer", %{
        "revision_digest" => missing_digest
      })

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.acceptance_signing_input(
               envelope(setup.issuer.kid, missing_acceptance),
               genesis_set
             )

    missing_termination =
      TerminationFixture.claims(setup.genesis, setup.issuer, "issuer", %{
        "governing_revision_digest" => missing_digest
      })

    assert {:error, %Error{code: :signing_refused}} =
             CharterAgreementProtocol.termination_signing_input(
               envelope(setup.issuer.kid, missing_termination),
               genesis_set
             )
  end

  test "the producer mints the ML-DSA-65 emission pair and refuses the others" do
    {ml_public, ml_private} = :crypto.generate_key(:mldsa65, [])

    claims = %{
      "protocol_revision" => 3,
      "descriptor_number" => 1,
      "verification_keys" => [
        %{
          "key_id" => "pq-key",
          "algorithm" => "ML-DSA-65",
          "public_key" => Base64Url.encode(ml_public),
          "status" => "active"
        }
      ],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:00Z"
    }

    assert {:ok, input} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => "pq-key",
               "claims" => claims,
               "algorithm" => "ML-DSA-65"
             })

    assert input.alg == "ML-DSA-65"

    {:ok, protected} = Base64Url.decode(input.protected_segment)
    assert protected == "{\"alg\":\"ML-DSA-65\",\"kid\":\"pq-key\",\"typ\":\"cap+party\"}"

    signature = :crypto.sign(:mldsa65, :none, input.message, ml_private)
    assert byte_size(signature) == 3309

    assert {:ok, compact} = CharterAgreementProtocol.assemble_compact(input, signature)

    assert {:ok, decoded} =
             CharterAgreementProtocol.decode_party_descriptor(compact, Limits.default())

    assert decoded.protocol_revision == 3

    # wrong emission revision for the selected algorithm
    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => "pq-key",
               "claims" => Map.put(claims, "protocol_revision", 2),
               "algorithm" => "ML-DSA-65"
             })

    # a non-emission registry name is never mintable
    assert {:error, %Error{code: :signing_input_invalid}} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => "pq-key",
               "claims" => claims,
               "algorithm" => "ML-DSA-87"
             })

    # classical emission still defaults
    {public, private} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<1>>, 32))

    classical = %{
      "protocol_revision" => 2,
      "descriptor_number" => 1,
      "verification_keys" => [
        %{
          "key_id" => "k",
          "algorithm" => "Ed25519",
          "public_key" => Base64Url.encode(public),
          "status" => "active"
        }
      ],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:00Z"
    }

    assert {:ok, default_input} =
             CharterAgreementProtocol.descriptor_signing_input(%{
               "kid" => "k",
               "claims" => classical
             })

    assert default_input.alg == "Ed25519"

    assert {:error, %Error{code: :signature_invalid}} =
             CharterAgreementProtocol.assemble_compact(default_input, <<0::512, 0>>)

    signed = :crypto.sign(:eddsa, :none, default_input.message, [private, :ed25519])
    assert {:ok, _compact} = CharterAgreementProtocol.assemble_compact(default_input, signed)
  end

  defp envelope(kid, claims), do: %{"kid" => kid, "claims" => mint(claims)}

  # Producer-side calls mint at the emission revision — exactly what a host
  # does after revision 2 (docs/adr/algorithm-name-agility.md): new minting
  # is exactly (Ed25519, 2).
  defp mint(claims),
    do: Map.put(claims, "protocol_revision", 2)

  defp sign(input, private_key),
    do: :crypto.sign(:eddsa, :none, input.message, [private_key, :ed25519])
end
