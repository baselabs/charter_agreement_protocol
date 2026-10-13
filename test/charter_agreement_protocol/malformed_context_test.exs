defmodule CharterAgreementProtocol.MalformedContextTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    Acceptance,
    Capability.Profile,
    ChainFixture,
    DescriptorChain,
    DescriptorFacts,
    Error,
    Internal.Retained,
    Limits,
    ReceiptFixture,
    TerminationNotice
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

  test "valid descriptive key values are reconstructed from retained bytes", context do
    descriptors =
      Enum.map(context.descriptors.descriptors, fn facts ->
        keys = Enum.map(facts.descriptor.verification_keys, &%{&1 | status: :retired})
        %{facts | descriptor: %{facts.descriptor | verification_keys: keys}}
      end)

    supplied = %{context.descriptors | descriptors: descriptors}
    compact = ChainFixture.acceptance(context.set.genesis, context.set.issuer, "issuer").compact

    assert {:ok, _facts} =
             CAP.verify_acceptance(compact, context.revision, supplied, Limits.default())
  end

  test "malformed context field types use invalid_type on every verifier", context do
    limits = Limits.default()

    acceptance =
      ChainFixture.acceptance(context.set.genesis, context.set.issuer, "issuer").compact

    for revision <- [
          %{context.revision | revision_number: "1"},
          %{context.revision | supersedes: [:x]}
        ],
        verify <- [&CAP.verify_acceptance/4, &CAP.verify_termination/4] do
      assert {:error, %Error{code: :invalid_type}} =
               verify.(acceptance, revision, context.descriptors, limits)

      assert {:error, %Error{code: :invalid_type}} =
               CAP.verify_receipt(context.receipt, revision, limits)
    end

    for chain <- [
          %{context.chain | chain_topology: :other},
          %{context.chain | not_verified: ["x"]}
        ] do
      assert {:error, %Error{code: :invalid_type}} =
               CAP.verify_receipt(context.receipt, chain, limits)
    end

    for verify <- [&CAP.verify_acceptance/4, &CAP.verify_termination/4] do
      assert {:error, %Error{code: :invalid_type}} =
               verify.(
                 acceptance,
                 context.revision,
                 %{context.descriptors | topology: nil},
                 limits
               )
    end

    predecessor = %{hd(context.descriptors.descriptors) | not_verified: ["x"]}

    assert {:error, %Error{code: :invalid_type}} =
             CAP.verify_descriptor(context.set.issuer.compact, predecessor, limits)
  end

  test "internal verified paths reject missing and extra chain fields", context do
    compact = ChainFixture.acceptance(context.set.genesis, context.set.issuer, "issuer").compact

    for chain <- [
          Map.delete(context.descriptors, :fork_evidence),
          Map.put(context.descriptors, :extra, nil)
        ],
        verify <- [&Acceptance.verify_verified/4, &TerminationNotice.verify_verified/4] do
      assert {:error, %Error{code: :invalid_type}} =
               verify.(compact, context.revision, chain, Limits.default())
    end

    refute Retained.compatible?([%{}], [%{}])
  end

  test "every context field rejects a malformed field type", context do
    limits = Limits.default()
    profile = Profile.full()
    [key] = context.set.issuer.claims["verification_keys"]
    public = Base.url_decode64!(key["public_key"], padding: false)

    descriptor_input = %{
      "kid" => context.set.issuer.kid,
      "claims" => Map.put(context.set.issuer.claims, "protocol_revision", 2),
      "public_key" => public
    }

    receipt_input = %{
      descriptor_input
      | "claims" => Map.put(ReceiptFixture.claims(context.set.genesis), "protocol_revision", 2)
    }

    compact = ChainFixture.acceptance(context.set.genesis, context.set.issuer, "issuer").compact

    for {value, kind, input} <- [
          {context.chain, :receipt, receipt_input},
          {context.revision, :receipt, receipt_input},
          {hd(context.descriptors.descriptors), :party_descriptor, descriptor_input}
        ],
        field <- Map.keys(Map.from_struct(value)) do
      changed = Map.put(value, field, fn -> :malformed end)
      assert {:error, %Error{}} = CAP.prepare_signing(kind, input, changed, limits, profile)

      assert {:error, %Error{}} =
               CAP.prepare_signing(kind, input, Map.delete(value, field), limits, profile)

      if kind == :party_descriptor,
        do:
          assert(
            match?(
              {:error, %Error{}},
              CAP.verify_descriptor(context.set.issuer.compact, changed, limits)
            )
          ),
        else:
          assert(match?({:error, %Error{}}, CAP.verify_receipt(context.receipt, changed, limits)))
    end

    for field <- Map.keys(Map.from_struct(context.revision)) do
      assert {:error, %Error{}} =
               CAP.verify_acceptance(
                 compact,
                 Map.delete(context.revision, field),
                 context.descriptors,
                 limits
               )

      assert {:error, %Error{}} =
               CAP.verify_termination(
                 compact,
                 Map.delete(context.revision, field),
                 context.descriptors,
                 limits
               )
    end

    [chain | rest] = context.chain.descriptor_chains
    malformed = %{context.chain | descriptor_chains: [%{chain | descriptors: [nil]} | rest]}
    assert {:error, %Error{}} = CAP.verify_receipt(context.receipt, malformed, limits)

    for field <- Map.keys(Map.from_struct(context.descriptors)) do
      changed = Map.put(context.descriptors, field, fn -> :malformed end)

      assert {:error, %Error{}} =
               CAP.verify_acceptance(
                 compact,
                 context.revision,
                 Map.delete(context.descriptors, field),
                 limits
               )

      assert {:error, %Error{}} =
               CAP.verify_termination(
                 compact,
                 context.revision,
                 Map.delete(context.descriptors, field),
                 limits
               )

      assert {:error, %Error{}} =
               CAP.verify_acceptance(compact, context.revision, changed, limits)

      assert {:error, %Error{}} =
               CAP.verify_termination(compact, context.revision, changed, limits)

      assert {:error, %Error{}} =
               Acceptance.verify_verified(compact, context.revision, changed, limits)

      assert {:error, %Error{}} =
               TerminationNotice.verify_verified(compact, context.revision, changed, limits)
    end
  end

  property "every context field remains total at the public verification and signing seams",
           context do
    check all(replacement <- one_of([term(), constant(["x" | :tail])]), max_runs: 25) do
      limits = Limits.default()
      profile = Profile.full()

      for value <- [
            context.chain,
            context.revision,
            context.descriptors,
            hd(context.descriptors.descriptors)
          ],
          field <- Map.keys(Map.from_struct(value)) do
        changed = Map.put(value, field, replacement)

        results = [
          CAP.verify_descriptor(context.set.issuer.compact, changed, limits),
          CAP.verify_receipt(context.receipt, changed, limits),
          CAP.verify_acceptance(context.set.issuer.compact, changed, changed, limits),
          CAP.verify_termination(context.set.issuer.compact, changed, changed, limits),
          CAP.verify_descriptor_chain(changed, limits),
          CAP.verify_chain(changed, changed, changed, changed, limits),
          CAP.verify_descriptor(context.set.issuer.compact, changed, limits, profile),
          CAP.verify_receipt(context.receipt, changed, limits, profile),
          CAP.verify_acceptance(context.set.issuer.compact, changed, changed, limits, profile),
          CAP.verify_termination(context.set.issuer.compact, changed, changed, limits, profile),
          CAP.verify_descriptor_chain(changed, limits, profile),
          CAP.verify_chain(changed, changed, changed, changed, limits, profile)
        ]

        assert Enum.all?(results, &typed?/1)

        for kind <- [:party_descriptor, :acceptance, :termination, :receipt] do
          claims =
            if kind == :party_descriptor,
              do: context.set.issuer.claims,
              else: ReceiptFixture.claims(context.set.genesis)

          [key] = context.set.issuer.claims["verification_keys"]

          input = %{
            "kid" => context.set.issuer.kid,
            "claims" => Map.put(claims, "protocol_revision", 2),
            "public_key" => Base.url_decode64!(key["public_key"], padding: false)
          }

          assert typed?(CAP.prepare_signing(kind, input, changed, limits, profile))
        end

        if is_struct(changed, CharterAgreementProtocol.CharterRevision) do
          assert typed?(
                   CAP.verify_acceptance(
                     context.set.issuer.compact,
                     changed,
                     context.descriptors,
                     limits
                   )
                 )

          assert typed?(
                   CAP.verify_termination(
                     context.set.issuer.compact,
                     changed,
                     context.descriptors,
                     limits
                   )
                 )
        end

        if is_struct(changed, DescriptorChain) do
          assert typed?(
                   CAP.verify_acceptance(
                     context.set.issuer.compact,
                     context.revision,
                     changed,
                     limits
                   )
                 )

          assert typed?(
                   CAP.verify_termination(
                     context.set.issuer.compact,
                     context.revision,
                     changed,
                     limits
                   )
                 )
        end
      end

      for field <-
            Map.keys(Map.from_struct(hd(context.chain.acceptance_facts).acceptance.envelope)) do
        [first | rest] = context.chain.acceptance_facts

        first =
          put_in(
            first.acceptance.envelope,
            Map.put(first.acceptance.envelope, field, replacement)
          )

        chain = %{context.chain | acceptance_facts: [first | rest]}
        assert typed?(CAP.verify_receipt(context.receipt, chain, limits))
      end
    end
  end

  property "valid retained prefixes reject bad tails and elements at depth", context do
    check all(
            depth <- integer(1..8),
            bad <- one_of([constant(:tail), constant(nil), constant(42)])
          ) do
      first = hd(context.descriptors.descriptors)
      prefix = List.duplicate(first, depth)
      improper = Enum.reduce(prefix, :tail, fn item, tail -> [item | tail] end)
      compact = ChainFixture.acceptance(context.set.genesis, context.set.issuer, "issuer").compact

      for descriptors <- [improper, prefix ++ [bad]],
          verify <- [&CAP.verify_acceptance/4, &CAP.verify_termination/4] do
        assert {:error, %Error{}} =
                 verify.(
                   compact,
                   context.revision,
                   %{context.descriptors | descriptors: descriptors},
                   Limits.default()
                 )
      end

      lineage =
        Enum.reduce(List.duplicate(context.set.issuer.compact, depth), :tail, fn item, tail ->
          [item | tail]
        end)

      malformed = %{first | lineage: lineage}

      assert {:error, %Error{}} =
               CAP.verify_descriptor(context.set.issuer.compact, malformed, Limits.default())

      assert {:error, %Error{}} =
               CAP.verify_acceptance(
                 compact,
                 context.revision,
                 %{context.descriptors | descriptors: [malformed]},
                 Limits.default()
               )
    end
  end

  defp typed?({:ok, _value}), do: true
  defp typed?({:error, %Error{}}), do: true
  defp typed?(_other), do: false
end
