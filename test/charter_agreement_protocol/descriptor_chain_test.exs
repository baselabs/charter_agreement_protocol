defmodule CharterAgreementProtocol.DescriptorChainTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{DescriptorChain, Error, ForkEvidence, Limits}
  alias CharterAgreementProtocol.DescriptorFixture

  test "linear chains retain every descriptor and assign head/superseded positions" do
    genesis = DescriptorFixture.genesis()
    second = DescriptorFixture.successor(genesis, 2)
    third = DescriptorFixture.successor(second, 3)

    assert {:ok, %DescriptorChain{topology: :linear, fork_evidence: nil} = chain} =
             CharterAgreementProtocol.verify_descriptor_chain(
               [third.compact, genesis.compact, second.compact],
               Limits.default()
             )

    positions = Map.new(chain.descriptors, &{&1.descriptor_digest, &1.descriptor_position})
    assert positions[genesis.digest] == :superseded
    assert positions[second.digest] == :superseded
    assert positions[third.digest] == :head
  end

  test "signed sibling successors produce fork facts and never a selected head" do
    genesis = DescriptorFixture.genesis()
    left = DescriptorFixture.successor(genesis, 2, key: DescriptorFixture.key(2, "left"))
    right = DescriptorFixture.successor(genesis, 2, key: DescriptorFixture.key(3, "right"))

    assert {:ok,
            %DescriptorChain{
              topology: :forked,
              fork_evidence: %ForkEvidence{kind: :sibling_descriptors} = evidence
            } = chain} =
             CharterAgreementProtocol.verify_descriptor_chain(
               [genesis.compact, left.compact, right.compact],
               Limits.default()
             )

    assert Enum.sort(evidence.sibling_descriptors) == Enum.sort([left.digest, right.digest])
    assert Enum.all?(chain.descriptors, &(&1.descriptor_position == :contested))
  end

  test "rejects disconnected, duplicate, and empty views without hiding input failures" do
    genesis = DescriptorFixture.genesis()

    orphan =
      DescriptorFixture.successor(genesis, 2,
        claims: %{"prev_descriptor_digest" => tagged_zero()}
      )

    for input <- [
          [],
          [genesis.compact, genesis.compact],
          [orphan.compact],
          [genesis.compact, orphan.compact]
        ] do
      assert {:error, %Error{code: :descriptor_chain_invalid}} =
               CharterAgreementProtocol.verify_descriptor_chain(input, Limits.default())
    end

    assert {:error, %Error{code: :invalid_type}} =
             DescriptorChain.verify(:not_a_list, Limits.default())

    invalid_limits = %{Limits.default() | max_bytes: -1}
    assert {:error, %Error{code: :invalid_limits}} = DescriptorChain.verify([], invalid_limits)
    assert {:error, %Error{code: :invalid_limits}} = DescriptorChain.verify(:bad, invalid_limits)
    assert {:error, %Error{code: :invalid_type}} = DescriptorChain.verify([], :bad)

    assert {:error, %Error{code: :descriptor_chain_invalid}} =
             DescriptorChain.verify(["not-a-jws"], Limits.default())

    {_wrong_key, wrong_private} = DescriptorFixture.key(9, "wrong-signer")

    child =
      DescriptorFixture.successor(genesis, 2,
        signing_private: wrong_private,
        kid: "genesis-key"
      )

    assert {:error, %Error{code: :descriptor_chain_invalid}} =
             DescriptorChain.verify([genesis.compact, child.compact], Limits.default())
  end

  defp tagged_zero, do: "sha-256:" <> String.duplicate("A", 43)
end
