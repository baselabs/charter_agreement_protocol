defmodule CharterAgreementProtocol.ReceiptTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    ChainFixture,
    CharterRevision,
    DescriptorChain,
    DescriptorFacts,
    Error,
    Limits,
    ReceiptFacts,
    ReceiptFixture,
    RevisionFacts,
    TerminationFacts
  }

  setup do
    setup = ChainFixture.base()
    limits = Limits.default()

    {:ok, chain} =
      CharterAgreementProtocol.verify_chain(
        [setup.genesis.bytes],
        setup.genesis
        |> ChainFixture.dual_acceptances(setup)
        |> Enum.map(& &1.compact),
        ChainFixture.descriptors(setup),
        [],
        limits
      )

    {:ok, revision} = CharterRevision.decode(setup.genesis.bytes, limits)
    %{setup: setup, chain: chain, revision: revision, limits: limits}
  end

  test "verifies a signed receipt against the retained chain", context do
    claims = ReceiptFixture.claims(context.setup.genesis)
    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:ok, %ReceiptFacts{} = facts} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)

    assert facts.receipt_digest == ReceiptFixture.digest(claims)
    assert facts.revision_number == 1
    assert facts.revision_digest == context.setup.genesis.digest
    assert facts.chain_conflict == :none
    assert facts.governing_match == :match
    assert facts.deployment_digest_matched
    assert facts.decision == :accepted
    assert facts.outcome == :effect_committed
    assert facts.signing_key_id == context.setup.issuer.kid
    refute :signature in facts.not_verified
    assert inspect(facts) == "#CharterAgreementProtocol.ReceiptFacts<redacted>"
  end

  test "revision-only context is explicit about unavailable signature and governance checks",
       context do
    claims = ReceiptFixture.claims(context.setup.genesis)
    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:ok, facts} =
             CharterAgreementProtocol.verify_receipt(compact, context.revision, context.limits)

    assert facts.chain_conflict == :none
    assert facts.governing_match == :undetermined
    assert facts.deployment_digest_matched
    assert :signature in facts.not_verified
    assert is_nil(facts.signing_key_id)
  end

  test "revision-only facts never promote an unverified signature hint", context do
    claims = ReceiptFixture.claims(context.setup.genesis)

    compact =
      ReceiptFixture.compact(claims, context.setup.issuer,
        private: context.setup.acceptor.private
      )

    assert {:ok, facts} =
             CharterAgreementProtocol.verify_receipt(compact, context.revision, context.limits)

    assert is_nil(facts.signing_key_id)
    assert :signature in facts.not_verified
  end

  test "an unrecognized receipt at an accepted number evidences a chain conflict", context do
    claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "revision_digest" =>
          CharterAgreementProtocol.CharterRevisionFixture.tagged(
            :charter_revision_content,
            "hidden-sibling"
          )
      })

    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:ok, facts} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)

    assert facts.chain_conflict == :fork_evidenced
    assert facts.governing_match == :mismatch
    refute facts.deployment_digest_matched
  end

  test "recognized revision digest cannot claim a different revision number", context do
    claims = ReceiptFixture.claims(context.setup.genesis, %{"revision_number" => 2})
    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:error, %Error{code: :receipt_claims_mismatch}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "deployment digest must be bound for the claimed agent role", context do
    claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "deployment_digest" =>
          CharterAgreementProtocol.CharterRevisionFixture.tagged(
            :legal_text,
            "unbound"
          )
      })

    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:error, %Error{code: :receipt_claims_mismatch}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "accepted indeterminate is representable", context do
    claims = ReceiptFixture.claims(context.setup.genesis, %{"outcome" => "indeterminate"})
    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:ok, %ReceiptFacts{decision: :accepted, outcome: :indeterminate}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "all permitted decision and settled-outcome projections are representable", context do
    for {decision, outcome, expected_decision, expected_outcome} <- [
          {"accepted", "no_effect", :accepted, :no_effect},
          {"rejected", "no_effect", :rejected, :no_effect}
        ] do
      claims =
        ReceiptFixture.claims(context.setup.genesis, %{
          "decision" => decision,
          "outcome" => outcome
        })

      compact = ReceiptFixture.compact(claims, context.setup.issuer)

      assert {:ok, %ReceiptFacts{decision: ^expected_decision, outcome: ^expected_outcome}} =
               CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
    end
  end

  test "host grant references may omit a BAP digest while BAP references may not", context do
    host_claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "grant" => %{"scheme" => "host", "id" => "host-grant-001"}
      })

    host_compact = ReceiptFixture.compact(host_claims, context.setup.issuer)

    assert {:ok, %ReceiptFacts{grant_scheme: :host, grant_digest: nil}} =
             CharterAgreementProtocol.verify_receipt(host_compact, context.chain, context.limits)

    bap_claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "grant" => %{"scheme" => "bap", "id" => "grant-001"}
      })

    bap_compact = ReceiptFixture.compact(bap_claims, context.setup.issuer)

    assert {:error, %Error{code: :receipt_invalid}} =
             CharterAgreementProtocol.verify_receipt(bap_compact, context.chain, context.limits)
  end

  test "retained chain facts are reverified before receipt projection", context do
    tampered = %{context.chain | accepted_revision_digests: [], chain_topology: :forked}

    compact =
      ReceiptFixture.compact(ReceiptFixture.claims(context.setup.genesis), context.setup.issuer)

    assert {:ok, %ReceiptFacts{chain_conflict: :none, governing_match: :match}} =
             CharterAgreementProtocol.verify_receipt(compact, tampered, context.limits)
  end

  test "malformed retained context fails closed at every artifact boundary", context do
    compact =
      ReceiptFixture.compact(ReceiptFixture.claims(context.setup.genesis), context.setup.issuer)

    [%RevisionFacts{} = revision_fact | revision_rest] = context.chain.revision_facts
    [%AcceptanceFacts{} = acceptance_fact | acceptance_rest] = context.chain.acceptance_facts

    [%DescriptorChain{} = descriptor_chain | descriptor_chain_rest] =
      context.chain.descriptor_chains

    [%DescriptorFacts{} = descriptor_fact | descriptor_rest] = descriptor_chain.descriptors

    malformed_revision_fact =
      %RevisionFacts{revision_fact | revision: %{revision_fact.revision | canonical_bytes: nil}}

    undecodable_revision_fact =
      %RevisionFacts{revision_fact | revision: %{revision_fact.revision | canonical_bytes: "bad"}}

    malformed_acceptance_fact = %AcceptanceFacts{acceptance_fact | acceptance: nil}
    malformed_descriptor_fact = %DescriptorFacts{descriptor_fact | lineage: nil}

    malformed_descriptor_chain =
      %DescriptorChain{
        descriptor_chain
        | descriptors: [malformed_descriptor_fact | descriptor_rest]
      }

    malformed_contexts = [
      %{context.chain | revision_facts: :not_a_list},
      %{context.chain | revision_facts: [malformed_revision_fact | revision_rest]},
      %{context.chain | revision_facts: [undecodable_revision_fact | revision_rest]},
      %{context.chain | acceptance_facts: :not_a_list},
      %{context.chain | acceptance_facts: [malformed_acceptance_fact | acceptance_rest]},
      %{context.chain | descriptor_chains: :not_a_list},
      %{context.chain | descriptor_chains: [nil]},
      %{context.chain | descriptor_chains: [nil | descriptor_chain_rest]},
      %{context.chain | descriptor_chains: [malformed_descriptor_chain | descriptor_chain_rest]},
      %{context.chain | termination_facts: :not_a_list},
      %{context.chain | termination_facts: [nil]}
    ]

    for malformed <- malformed_contexts do
      assert {:error, %Error{}} =
               CharterAgreementProtocol.verify_receipt(compact, malformed, context.limits)
    end
  end

  test "retained termination envelopes participate in cold re-verification", context do
    termination =
      ChainFixture.termination(context.setup.genesis, context.setup.issuer, "issuer", %{
        "effective_at" => "2026-08-26T13:00:00Z"
      })

    assert {:ok, chain} =
             CharterAgreementProtocol.verify_chain(
               [context.setup.genesis.bytes],
               context.setup.genesis
               |> ChainFixture.dual_acceptances(context.setup)
               |> Enum.map(& &1.compact),
               ChainFixture.descriptors(context.setup),
               [termination.compact],
               context.limits
             )

    assert [%TerminationFacts{}] = chain.termination_facts

    compact =
      ReceiptFixture.compact(ReceiptFixture.claims(context.setup.genesis), context.setup.issuer)

    assert {:ok, %ReceiptFacts{governing_match: :match}} =
             CharterAgreementProtocol.verify_receipt(compact, chain, context.limits)
  end

  test "recognized forked revision reports undetermined governance without a tie-break",
       context do
    left = ChainFixture.successor(context.setup.genesis, 2, legal_text: "left\n")
    right = ChainFixture.successor(context.setup.genesis, 2, legal_text: "right\n")
    revisions = [context.setup.genesis, left, right]
    acceptances = Enum.flat_map(revisions, &ChainFixture.dual_acceptances(&1, context.setup))

    assert {:ok, chain} =
             CharterAgreementProtocol.verify_chain(
               Enum.map(revisions, & &1.bytes),
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(context.setup),
               [],
               context.limits
             )

    compact =
      left
      |> ReceiptFixture.claims(%{"occurred_at" => "2026-08-25T12:00:01Z"})
      |> ReceiptFixture.compact(context.setup.issuer)

    assert {:ok, %ReceiptFacts{governing_match: :undetermined, chain_conflict: :none}} =
             CharterAgreementProtocol.verify_receipt(compact, chain, context.limits)
  end

  test "unknown receipt roles fail before an interested-party signature can promote them",
       context do
    unknown_digest =
      CharterAgreementProtocol.CharterRevisionFixture.tagged(
        :charter_revision_content,
        "unknown-role-revision"
      )

    claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "revision_digest" => unknown_digest,
        "issuing_party_role" => "intruder"
      })

    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:error, %Error{code: :receipt_claims_mismatch}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "a proposed role-swapped revision cannot promote the counterparty key", context do
    role_swapped =
      ChainFixture.successor(context.setup.genesis, 2,
        claims: %{
          "parties" => [
            %{
              "party_descriptor_digest" => context.setup.acceptor.digest,
              "role" => "issuer"
            },
            %{
              "party_descriptor_digest" => context.setup.issuer.digest,
              "role" => "acceptor"
            }
          ]
        }
      )

    assert {:ok, chain} =
             CharterAgreementProtocol.verify_chain(
               [context.setup.genesis.bytes, role_swapped.bytes],
               context.setup.genesis
               |> ChainFixture.dual_acceptances(context.setup)
               |> Enum.map(& &1.compact),
               ChainFixture.descriptors(context.setup),
               [],
               context.limits
             )

    compact =
      role_swapped
      |> ReceiptFixture.claims()
      |> ReceiptFixture.compact(context.setup.acceptor)

    assert {:error, %Error{code: :signature_invalid}} =
             CharterAgreementProtocol.verify_receipt(compact, chain, context.limits)
  end

  test "digest decoding and revision re-verification reject canonical-looking bad inputs",
       context do
    noncanonical_digest = "sha-256:" <> String.duplicate("A", 42) <> "B"

    compact =
      context.setup.genesis
      |> ReceiptFixture.claims(%{"revision_digest" => noncanonical_digest})
      |> ReceiptFixture.compact(context.setup.issuer)

    assert {:error, %Error{code: :receipt_invalid}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)

    good_compact =
      ReceiptFixture.compact(ReceiptFixture.claims(context.setup.genesis), context.setup.issuer)

    malformed_revision = %{context.revision | canonical_bytes: "bad"}

    assert {:error, %Error{code: :invalid_syntax}} =
             CharterAgreementProtocol.verify_receipt(
               good_compact,
               malformed_revision,
               context.limits
             )
  end

  test "rejected receipts require no_effect", context do
    claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "decision" => "rejected",
        "outcome" => "effect_committed"
      })

    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:error, %Error{code: :cross_field_invalid}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "indeterminate requires an accepted decision", context do
    claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "decision" => "rejected",
        "outcome" => "indeterminate"
      })

    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:error, %Error{code: :cross_field_invalid}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "recorded_at cannot precede occurred_at", context do
    claims =
      ReceiptFixture.claims(context.setup.genesis, %{
        "recorded_at" => "2026-08-25T11:59:59Z"
      })

    compact = ReceiptFixture.compact(claims, context.setup.issuer)

    assert {:error, %Error{code: :receipt_invalid}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "wrong receipt signature fails closed in chain context", context do
    claims = ReceiptFixture.claims(context.setup.genesis)

    compact =
      ReceiptFixture.compact(claims, context.setup.issuer,
        private: context.setup.acceptor.private
      )

    assert {:error, %Error{code: :signature_invalid}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, context.limits)
  end

  test "invalid limits and type boundaries are total", context do
    compact =
      ReceiptFixture.compact(ReceiptFixture.claims(context.setup.genesis), context.setup.issuer)

    %Limits{} = limits = context.limits

    assert {:error, %Error{code: :invalid_limits}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, %Limits{
               limits
               | max_bytes: -1
             })

    assert {:error, %Error{code: :invalid_type}} =
             CharterAgreementProtocol.verify_receipt(compact, :not_context, context.limits)

    assert {:error, %Error{code: :invalid_type}} =
             CharterAgreementProtocol.verify_receipt(compact, context.chain, :not_limits)
  end
end
