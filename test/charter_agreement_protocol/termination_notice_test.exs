defmodule CharterAgreementProtocol.TerminationNoticeTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    CharterRevisionFixture,
    DescriptorFixture,
    Error,
    Limits,
    TerminationFacts,
    TerminationFixture,
    TerminationNotice
  }

  test "verifies a listed-reason notice through the facade" do
    setup = setup_notice()

    assert {:ok, %TerminationFacts{} = facts} =
             CharterAgreementProtocol.verify_termination(
               setup.notice.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    assert facts.termination_digest == setup.notice.digest
    assert facts.governing_revision_digest == setup.revision_fixture.digest
    assert facts.reason_code == "mutual"
    assert facts.descriptor_position == :head
  end

  test "rejects unlisted reason and every referenced-artifact mismatch" do
    setup = setup_notice()
    zero = "sha-256:" <> String.duplicate("A", 43)

    variants = [
      %{"charter_id" => zero},
      %{"governing_revision_digest" => zero},
      %{"party_descriptor_digest" => setup.acceptor.digest},
      %{"party_role" => "acceptor"},
      %{"reason_code" => "not-listed"}
    ]

    for overrides <- variants do
      notice = signed_notice(setup, overrides)

      assert {:error, %Error{code: :termination_claims_mismatch}} =
               TerminationNotice.verify(
                 notice.compact,
                 setup.revision,
                 setup.chain,
                 Limits.default()
               )
    end
  end

  test "requires issued_at at or before effective_at and retains opaque detail digest" do
    setup = setup_notice()

    after_effective =
      signed_notice(setup, %{
        "issued_at" => "2026-08-26T13:00:01Z",
        "effective_at" => "2026-08-26T13:00:00Z"
      })

    assert {:error, %Error{code: :termination_invalid}} =
             TerminationNotice.verify(
               after_effective.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    detail = "sha-256:" <> String.duplicate("A", 43)

    equal =
      signed_notice(setup, %{
        "issued_at" => "2026-08-26T13:00:00Z",
        "effective_at" => "2026-08-26T13:00:00Z",
        "detail_digest" => detail
      })

    assert {:ok, %TerminationFacts{detail_digest: ^detail}} =
             TerminationNotice.verify(
               equal.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )
  end

  test "rejects wrong signature and forged inputs while retaining descriptor position" do
    setup = setup_notice()
    {_key, wrong_private} = DescriptorFixture.key(9, "wrong")
    wrong = signed_notice(setup, %{}, private: wrong_private)

    assert {:error, %Error{code: :signature_invalid}} =
             TerminationNotice.verify(
               wrong.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    successor = DescriptorFixture.successor(setup.issuer, 2)

    {:ok, chain} =
      CharterAgreementProtocol.verify_descriptor_chain(
        [setup.issuer.compact, successor.compact],
        Limits.default()
      )

    assert {:ok, %TerminationFacts{descriptor_position: :superseded}} =
             TerminationNotice.verify(
               setup.notice.compact,
               %{setup.revision | revision_number: 99},
               chain,
               Limits.default()
             )

    assert {:error, %Error{code: :invalid_type}} =
             TerminationNotice.verify(:bad, setup.revision, setup.chain, %{})
  end

  test "fails closed on invalid limits, signed digests, keys, and retained chain views" do
    setup = setup_notice()
    invalid_limits = %{Limits.default() | max_bytes: -1}

    assert {:error, %Error{code: :invalid_limits}} =
             TerminationNotice.verify(
               setup.notice.compact,
               setup.revision,
               setup.chain,
               invalid_limits
             )

    assert {:error, %Error{code: :invalid_type}} =
             TerminationNotice.verify(
               setup.notice.compact,
               :not_a_revision,
               setup.chain,
               Limits.default()
             )

    assert {:error, %Error{code: :invalid_limits}} =
             TerminationNotice.verify(
               setup.notice.compact,
               :not_a_revision,
               setup.chain,
               invalid_limits
             )

    non_canonical_digest = "sha-256:" <> String.duplicate("A", 42) <> "B"
    invalid_digest = signed_notice(setup, %{"detail_digest" => non_canonical_digest})

    assert {:error, %Error{code: :termination_invalid}} =
             TerminationNotice.verify(
               invalid_digest.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    unknown_key = signed_notice(setup, %{}, kid: "unknown-key")

    assert {:error, %Error{code: :termination_invalid}} =
             TerminationNotice.verify(
               unknown_key.compact,
               setup.revision,
               setup.chain,
               Limits.default()
             )

    for descriptors <- [[], [%{}], :not_a_list] do
      forged_chain = %{setup.chain | descriptors: descriptors}

      assert {:error, %Error{code: :descriptor_chain_invalid}} =
               TerminationNotice.verify(
                 setup.notice.compact,
                 setup.revision,
                 forged_chain,
                 Limits.default()
               )
    end
  end

  defp setup_notice do
    issuer = DescriptorFixture.genesis()
    acceptor = DescriptorFixture.genesis(key: DescriptorFixture.key(2, "acceptor-key"))

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

    {:ok, chain} =
      CharterAgreementProtocol.verify_descriptor_chain([issuer.compact], Limits.default())

    base = %{issuer: issuer, acceptor: acceptor, revision_fixture: revision_fixture}
    notice = signed_notice(base)
    Map.merge(base, %{revision: revision, chain: chain, notice: notice})
  end

  defp signed_notice(setup, overrides \\ %{}, options \\ []) do
    setup.revision_fixture
    |> TerminationFixture.claims(setup.issuer, "issuer", overrides)
    |> TerminationFixture.compact(setup.issuer, options)
  end
end
