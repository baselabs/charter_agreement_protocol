defmodule CharterAgreementProtocol.Architecture.AlgorithmNameAgilityTest do
  @moduledoc """
  The revision-2 alg-name contract (docs/adr/algorithm-name-agility.md):
  the closed registry, the per-artifact binding rule, the emission
  contract, and the mixed-revision composition that keeps charters
  verifiable across revisions. The (rev 1, Ed25519) negative and the
  revision-3 fail-closed case are the per-name negatives the certified
  corpus also carries — these are their red-provable local forms.
  """

  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    AcceptanceFixture,
    ChainFixture,
    DescriptorFixture,
    Error,
    Limits
  }

  alias CharterAgreementProtocol, as: CAP

  test "the registry is the closed two-row set with the binding columns" do
    assert CAP.Algorithm.registry() == [
             %{name: "EdDSA", min_protocol_revision: 1, key_algorithm: "Ed25519"},
             %{name: "Ed25519", min_protocol_revision: 2, key_algorithm: "Ed25519"}
           ]

    assert CAP.Algorithm.accepted_protocol_revisions() == [1, 2]
    assert CAP.Algorithm.emission_name() == "Ed25519"
    assert CAP.Algorithm.emission_protocol_revision() == 2
  end

  test "the binding rule binds the name to the revision, per artifact" do
    # EdDSA: any accepted revision
    assert CAP.Algorithm.binds?("EdDSA", 1)
    assert CAP.Algorithm.binds?("EdDSA", 2)

    # Ed25519: from revision 2 only — the rule's red edge
    assert CAP.Algorithm.binds?("Ed25519", 2)
    refute CAP.Algorithm.binds?("Ed25519", 1)

    # Unknown revisions fail closed; unknown names are not registry rows
    refute CAP.Algorithm.binds?("EdDSA", 3)
    refute CAP.Algorithm.binds?("Ed25519", 3)
    refute CAP.Algorithm.binds?("Ed448", 2)
    refute CAP.Algorithm.binds?("edsa", 1)
    refute CAP.Algorithm.binds?(42, 1)
    refute CAP.Algorithm.binds?("EdDSA", "1")
  end

  test "non-registry names are not accepted names" do
    assert CAP.Algorithm.accepted_name?("EdDSA")
    assert CAP.Algorithm.accepted_name?("Ed25519")
    refute CAP.Algorithm.accepted_name?("Ed448")
    refute CAP.Algorithm.accepted_name?("edsa")
    refute CAP.Algorithm.accepted_name?(42)
  end

  test "an unknown alg name is rejected at the framing layer" do
    descriptor = DescriptorFixture.genesis()

    compact =
      DescriptorFixture.compact(descriptor.claims, descriptor.kid, descriptor.private,
        protected: %{"alg" => "Ed448", "typ" => "cap+party", "kid" => descriptor.kid}
      ).compact

    assert {:error, %Error{code: :protected_header_invalid}} =
             CAP.decode_party_descriptor(compact, Limits.default())
  end

  test "(rev 1, Ed25519) is rejected at the framing layer — the per-name negative" do
    descriptor = DescriptorFixture.genesis()

    compact =
      DescriptorFixture.compact(descriptor.claims, descriptor.kid, descriptor.private,
        protected: %{"alg" => "Ed25519", "typ" => "cap+party", "kid" => descriptor.kid}
      ).compact

    assert {:error, %Error{code: :protected_header_invalid}} =
             CAP.decode_party_descriptor(compact, Limits.default())
  end

  test "(rev 2, EdDSA) — the compatibility case — decodes and verifies" do
    descriptor = DescriptorFixture.genesis()
    claims2 = Map.put(descriptor.claims, "protocol_revision", 2)

    compact = DescriptorFixture.compact(claims2, descriptor.kid, descriptor.private).compact

    assert {:ok, _facts} = CAP.verify_descriptor(compact, nil, Limits.default())
  end

  test "(rev 2, Ed25519) decodes and verifies" do
    descriptor = DescriptorFixture.genesis()
    claims2 = Map.put(descriptor.claims, "protocol_revision", 2)

    compact =
      DescriptorFixture.compact(claims2, descriptor.kid, descriptor.private,
        protected: %{"alg" => "Ed25519", "typ" => "cap+party", "kid" => descriptor.kid}
      ).compact

    assert {:ok, _facts} = CAP.verify_descriptor(compact, nil, Limits.default())
  end

  test "a non-object payload fails the binding layer closed" do
    descriptor = DescriptorFixture.genesis()

    forged =
      descriptor.compact
      |> String.split(".")
      |> List.replace_at(1, "W10")
      |> Enum.join(".")

    assert {:error, %Error{code: :protected_header_invalid}} =
             CAP.decode_party_descriptor(forged, Limits.default())
  end

  test "revision 3 fails closed at the framing layer" do
    descriptor = DescriptorFixture.genesis()
    claims3 = Map.put(descriptor.claims, "protocol_revision", 3)

    compact = DescriptorFixture.compact(claims3, descriptor.kid, descriptor.private).compact

    assert {:error, %Error{}} = CAP.decode_party_descriptor(compact, Limits.default())
  end

  test "the producer refuses to mint at a non-current revision" do
    descriptor = DescriptorFixture.genesis()

    assert {:error, %Error{code: :signing_input_invalid}} =
             CAP.descriptor_signing_input(%{
               "kid" => descriptor.kid,
               "claims" => descriptor.claims
             })
  end

  test "a revision-2 acceptance anchors a revision-1 charter (the mixed view)" do
    setup = ChainFixture.base()

    {:ok, set} =
      CharterAgreementProtocol.ArtifactSet.build(
        [setup.genesis.bytes],
        [],
        [],
        ChainFixture.descriptors(setup)
      )

    claims =
      AcceptanceFixture.claims(setup.genesis, setup.issuer, "issuer")
      |> Map.put("protocol_revision", 2)

    assert {:ok, input} =
             CAP.acceptance_signing_input(%{"kid" => setup.issuer.kid, "claims" => claims}, set)

    signature =
      :crypto.sign(:eddsa, :none, input.message, [setup.issuer.private, :ed25519])

    assert {:ok, compact} = CAP.assemble_compact(input, signature)

    # The anchored revision is a revision-1 fixture; the acceptance carries
    # revision 2 with the Ed25519 header. Both verify; the view is mixed.
    {:ok, revision} = CAP.decode_charter_revision(setup.genesis.bytes, Limits.default())
    {:ok, chain} = CAP.verify_descriptor_chain([setup.issuer.compact], Limits.default())

    assert {:ok, _facts} = CAP.verify_acceptance(compact, revision, chain, Limits.default())
  end
end
