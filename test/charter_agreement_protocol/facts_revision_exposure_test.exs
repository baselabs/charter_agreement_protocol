defmodule CharterAgreementProtocol.FactsRevisionExposureTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Chain, ChainFixture, Limits, Receipt, ReceiptFixture}

  setup do
    setup = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)
    compacts = Enum.map(acceptances, & &1.compact)

    {:ok, facts} =
      Chain.verify([setup.genesis.bytes], compacts, ChainFixture.descriptors(setup), [], Limits.default())

    %{setup: setup, facts: facts}
  end

  test "every facts record carries its artifact's protocol revision", %{facts: facts} do
    for revision_fact <- facts.revision_facts do
      assert revision_fact.protocol_revision == 1
    end

    for acceptance_fact <- facts.acceptance_facts do
      assert acceptance_fact.protocol_revision == 1
    end

    for chain <- facts.descriptor_chains do
      for descriptor_fact <- chain.descriptors do
        assert descriptor_fact.protocol_revision == 1
      end
    end
  end

  test "signed-artifact facts carry the envelope alg name; unsigned revisions carry none",
       %{facts: facts} do
    for acceptance_fact <- facts.acceptance_facts do
      assert acceptance_fact.alg == "EdDSA"
    end

    for chain <- facts.descriptor_chains do
      for descriptor_fact <- chain.descriptors do
        assert descriptor_fact.alg == "EdDSA"
      end
    end

    # Unsigned charter revisions have no envelope: the scalar is nil, not a guess.
    for revision_fact <- facts.revision_facts do
      assert is_nil(revision_fact.alg)
    end
  end

  test "a verified receipt's facts carry revision and alg (the only route to them)",
       %{setup: setup, facts: facts} do
    claims = ReceiptFixture.claims(setup.genesis)
    compact = ReceiptFixture.compact(claims, setup.issuer)
    {:ok, receipt_facts} = Receipt.verify(compact, facts, Limits.default())
    assert receipt_facts.protocol_revision == 1
    assert receipt_facts.alg == "EdDSA"
  end
end
