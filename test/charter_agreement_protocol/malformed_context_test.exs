defmodule CharterAgreementProtocol.MalformedContextTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    ChainFixture,
    DescriptorChain,
    DescriptorFacts,
    Error,
    Limits,
    ReceiptFixture
  }

  setup do
    set = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(set.genesis, set) |> Enum.map(& &1.compact)

    {:ok, chain} =
      CAP.verify_chain(
        [set.genesis.bytes],
        acceptances,
        ChainFixture.descriptors(set),
        [],
        Limits.default()
      )

    {:ok, revision} = CAP.decode_charter_revision(set.genesis.bytes, Limits.default())
    {:ok, descriptors} = CAP.verify_descriptor_chain([set.issuer.compact], Limits.default())

    %{
      set: set,
      chain: chain,
      revision: revision,
      descriptors: descriptors,
      receipt: ReceiptFixture.compact(ReceiptFixture.claims(set.genesis), set.issuer)
    }
  end

  for {field, value} <- [signature: :not_binary, message: 42] do
    test "receipt rejects a malformed retained #{field}", context do
      [first | rest] = context.chain.acceptance_facts
      envelope = Map.put(first.acceptance.envelope, unquote(field), unquote(value))
      first = %{first | acceptance: %{first.acceptance | envelope: envelope}}

      assert {:error, %Error{}} =
               CAP.verify_receipt(
                 context.receipt,
                 %{context.chain | acceptance_facts: [first | rest]},
                 Limits.default()
               )
    end
  end

  test "acceptance rejects an improper retained lineage", context do
    bad =
      struct(DescriptorChain,
        topology: :linear,
        descriptors: [struct(DescriptorFacts, lineage: [context.set.issuer.compact | :tail])]
      )

    compact = ChainFixture.acceptance(context.set.genesis, context.set.issuer, "issuer").compact

    assert {:error, %Error{}} =
             CAP.verify_acceptance(compact, context.revision, bad, Limits.default())
  end

  test "descriptor rejects an improper predecessor lineage", context do
    bad =
      struct(DescriptorFacts,
        lineage: [context.set.issuer.compact | :tail],
        descriptor_digest: "x"
      )

    assert {:error, %Error{}} =
             CAP.verify_descriptor(context.set.issuer.compact, bad, Limits.default())
  end
end
