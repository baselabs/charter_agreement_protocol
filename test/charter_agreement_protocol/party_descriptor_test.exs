defmodule CharterAgreementProtocol.PartyDescriptorTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    Base64Url,
    CompactJws,
    DescriptorFacts,
    Error,
    Limits,
    PartyDescriptor,
    Signature
  }

  alias CharterAgreementProtocol.DescriptorFixture

  test "decodes and verifies a canonical self-signed genesis descriptor" do
    fixture = DescriptorFixture.genesis()

    assert {:ok, descriptor} =
             CharterAgreementProtocol.decode_party_descriptor(fixture.compact, Limits.default())

    assert descriptor.descriptor_number == 1
    assert descriptor.party_id == nil
    assert descriptor.prev_descriptor_digest == nil
    assert descriptor.envelope.kid == "genesis-key"
    assert CharterAgreementProtocol.descriptor_digest(descriptor) == fixture.digest

    assert {:ok, %DescriptorFacts{} = facts} =
             CharterAgreementProtocol.verify_descriptor(fixture.compact, nil, Limits.default())

    assert facts.party_id == fixture.digest
    assert facts.descriptor_digest == fixture.digest
    assert facts.descriptor_number == 1
    assert facts.signing_key_id == "genesis-key"
  end

  test "verifies a successor only with the active predecessor key and exact chain coordinates" do
    genesis = DescriptorFixture.genesis()

    {:ok, predecessor} =
      CharterAgreementProtocol.verify_descriptor(genesis.compact, nil, Limits.default())

    successor = DescriptorFixture.successor(genesis, 2)

    assert {:ok, facts} =
             CharterAgreementProtocol.verify_descriptor(
               successor.compact,
               predecessor,
               Limits.default()
             )

    assert facts.party_id == genesis.digest
    assert facts.prev_descriptor_digest == genesis.digest
    assert facts.descriptor_number == 2

    {_new_key, new_private} = DescriptorFixture.key(9, "new-key")

    signed_by_new =
      DescriptorFixture.successor(genesis, 2, signing_private: new_private, kid: "new-key")

    assert_error(signed_by_new.compact, predecessor, :descriptor_key_invalid)

    {retired, retired_private} = DescriptorFixture.key(1, "genesis-key", "retired")
    {active, _active_private} = DescriptorFixture.key(2, "active-key")

    retired_genesis =
      DescriptorFixture.genesis(
        key: {retired, retired_private},
        claims: %{"verification_keys" => [retired, active]}
      )

    assert_error(retired_genesis.compact, nil, :descriptor_key_invalid)
  end

  test "rejects successor identity, predecessor digest, and monotonic-number divergence" do
    genesis = DescriptorFixture.genesis()

    {:ok, predecessor} =
      CharterAgreementProtocol.verify_descriptor(genesis.compact, nil, Limits.default())

    wrong_party = DescriptorFixture.successor(genesis, 2, claims: %{"party_id" => tagged_zero()})

    wrong_prev =
      DescriptorFixture.successor(genesis, 2,
        claims: %{"prev_descriptor_digest" => tagged_zero()}
      )

    wrong_number = DescriptorFixture.successor(genesis, 3)

    for fixture <- [wrong_party, wrong_prev, wrong_number] do
      assert_error(fixture.compact, predecessor, :descriptor_chain_invalid)
    end
  end

  test "enforces key grammar, algorithm, canonical 32-byte public key, uniqueness, and active census" do
    {key, _private} = DescriptorFixture.key(1, "good")

    variants = [
      [%{key | "key_id" => "bad kid"}],
      [%{key | "algorithm" => "X25519"}],
      [%{key | "public_key" => "AQ"}],
      [key, key],
      [%{key | "status" => "retired"}]
    ]

    for keys <- variants do
      fixture = DescriptorFixture.genesis(claims: %{"verification_keys" => keys})
      assert {:error, %Error{}} = PartyDescriptor.verify(fixture.compact, nil, Limits.default())
    end
  end

  test "enforces exact outer and nested member worlds, bounds, and UTC timestamp" do
    base = DescriptorFixture.genesis()
    key = hd(base.claims["verification_keys"])

    fixtures = [
      DescriptorFixture.genesis(claims: %{"rogue" => true}),
      DescriptorFixture.genesis(claims: %{"effective_from" => "2026-08-25T10:00:00+00:00"}),
      DescriptorFixture.genesis(claims: %{"verification_keys" => [Map.put(key, "rogue", true)]}),
      DescriptorFixture.genesis(
        claims: %{
          "attestation_hints" =>
            List.duplicate(%{"kind" => "x", "uri" => "https://example.com"}, 17)
        }
      )
    ]

    for fixture <- fixtures do
      assert {:error, %Error{}} = PartyDescriptor.decode(fixture.compact, Limits.default())
    end
  end

  test "rejects noncanonical payload/header bytes, wrong typ, malformed signatures, and improper terms" do
    fixture =
      DescriptorFixture.genesis(
        protected: %{"alg" => "EdDSA", "typ" => "cap+acceptance", "kid" => "genesis-key"}
      )

    assert_error(fixture.compact, nil, :protected_header_invalid)

    valid = DescriptorFixture.genesis()
    [protected, payload, signature] = String.split(valid.compact, ".")
    size = byte_size(signature) - 1
    prefix = binary_part(signature, 0, size)
    last = :binary.last(signature)
    replacement = if last == ?A, do: "B", else: "A"
    tampered = protected <> "." <> payload <> "." <> prefix <> replacement

    assert {:error, %Error{code: :signature_invalid}} =
             PartyDescriptor.verify(tampered, nil, Limits.default())

    assert {:error, %Error{code: :invalid_type}} =
             PartyDescriptor.decode(:not_bytes, Limits.default())

    assert {:error, %Error{}} = PartyDescriptor.decode("not-a-jws", Limits.default())
  end

  test "rejects the backend's trivial low-order Ed25519 forgery" do
    {key, private} = DescriptorFixture.key(8, "low-order-key")
    identity_key = %{key | "public_key" => Base64Url.encode(<<1, 0::248>>)}
    descriptor = DescriptorFixture.genesis(key: {identity_key, private})
    [protected, payload, _signature] = String.split(descriptor.compact, ".")

    forged = protected <> "." <> payload <> "." <> Base64Url.encode(<<1, 0::504>>)

    assert {:error, %Error{code: :signature_invalid}} =
             PartyDescriptor.verify(forged, nil, Limits.default())
  end

  test "strict Ed25519 verification rejects the complete torsion set and noncanonical inputs" do
    torsion = [
      "0100000000000000000000000000000000000000000000000000000000000000",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
      "0000000000000000000000000000000000000000000000000000000000000080",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
      "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
      "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
      "0000000000000000000000000000000000000000000000000000000000000000",
      "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa"
    ]

    for hex <- torsion do
      point = Base.decode16!(hex, case: :mixed)

      assert {:error, %Error{code: :signature_invalid}} =
               Signature.verify("message", point <> <<0::256>>, point)
    end

    noncanonical_y = Base.decode16!("ed" <> String.duplicate("ff", 30) <> "7f", case: :mixed)
    negative_zero = <<1, 0::240, 128>>

    for point <- [noncanonical_y, negative_zero] do
      assert {:error, %Error{code: :signature_invalid}} =
               Signature.verify("message", point <> <<0::256>>, point)
    end

    fixture = DescriptorFixture.genesis()

    {:ok, envelope} =
      CompactJws.parse(fixture.compact, "cap+party", Limits.default())

    {:ok, public_key} =
      fixture.claims["verification_keys"]
      |> hd()
      |> Map.fetch!("public_key")
      |> Base64Url.decode()

    <<r::binary-size(32), _scalar::binary-size(32)>> = envelope.signature

    subgroup_order =
      Base.decode16!(
        "edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010",
        case: :mixed
      )

    assert {:error, %Error{code: :signature_invalid}} =
             Signature.verify(envelope.message, r <> subgroup_order, public_key)
  end

  test "compact envelope parser is total across bounds, segment, canonical, header, and key failures" do
    valid = DescriptorFixture.genesis()
    [protected, payload, signature] = String.split(valid.compact, ".")
    invalid_limits = %{Limits.default() | max_bytes: -1}

    assert_error_code(
      CompactJws.parse(valid.compact, "cap+party", invalid_limits),
      :invalid_limits
    )

    assert_error_code(CompactJws.parse(valid.compact, "cap+party", :bad), :invalid_type)

    assert_error_code(
      CompactJws.parse("*.#{payload}.#{signature}", "cap+party", Limits.default()),
      :compact_invalid
    )

    assert_error_code(
      CompactJws.parse("#{protected}.#{payload}.AQ", "cap+party", Limits.default()),
      :signature_invalid
    )

    noncanonical_header =
      Base.url_encode64(~s({"typ":"cap+party","kid":"genesis-key","alg":"EdDSA"}), padding: false)

    noncanonical_payload =
      Base.url_encode64(Base.url_decode64!(payload, padding: false) <> " ", padding: false)

    array_header = Base.url_encode64("[]", padding: false)

    assert_error_code(
      CompactJws.parse(
        "#{noncanonical_header}.#{payload}.#{signature}",
        "cap+party",
        Limits.default()
      ),
      :protected_header_invalid
    )

    assert_error_code(
      CompactJws.parse(
        "#{protected}.#{noncanonical_payload}.#{signature}",
        "cap+party",
        Limits.default()
      ),
      :non_canonical_bytes
    )

    assert_error_code(
      CompactJws.parse("#{array_header}.#{payload}.#{signature}", "cap+party", Limits.default()),
      :protected_header_invalid
    )

    for kid <- [String.duplicate("a", 129), "bad kid"] do
      fixture =
        DescriptorFixture.genesis(
          protected: %{"alg" => "EdDSA", "typ" => "cap+party", "kid" => kid}
        )

      assert_error_code(
        CompactJws.parse(fixture.compact, "cap+party", Limits.default()),
        :protected_header_invalid
      )
    end

    assert_error_code(CompactJws.verify_signature(%{}, <<0::256>>), :signature_invalid)
    {:ok, envelope} = CompactJws.parse(valid.compact, "cap+party", Limits.default())
    assert_error_code(CompactJws.verify_signature(envelope, <<0>>), :signature_invalid)

    malformed_envelope = %{envelope | signature: :not_signature_bytes}

    assert_error_code(
      CompactJws.verify_signature(malformed_envelope, <<0::256>>),
      :signature_invalid
    )
  end

  test "descriptor extraction and predecessor revalidation fail closed on forged edge shapes" do
    genesis =
      DescriptorFixture.genesis(
        claims: %{
          "attestation_hints" => [
            %{"kind" => "vlei", "uri" => "https://example.com/hint"}
          ]
        }
      )

    assert {:ok, descriptor} = PartyDescriptor.decode(genesis.compact, Limits.default())
    assert [%PartyDescriptor.AttestationHint{kind: "vlei"}] = descriptor.attestation_hints

    bad_extension = DescriptorFixture.genesis(claims: %{"extensions" => %{"critical" => %{}}})

    bad_digest =
      DescriptorFixture.successor(genesis, 2,
        claims: %{"party_id" => "sha-256:" <> String.duplicate("A", 42) <> "B"}
      )

    malformed_key =
      genesis.claims["verification_keys"]
      |> hd()
      |> Map.put("public_key", String.duplicate("A", 42) <> "B")

    bad_public_key =
      DescriptorFixture.genesis(claims: %{"verification_keys" => [malformed_key]})

    bad_genesis_shape = DescriptorFixture.genesis(claims: %{"party_id" => tagged_zero()})

    for fixture <- [bad_extension, bad_digest, bad_public_key, bad_genesis_shape] do
      assert {:error, %Error{}} = PartyDescriptor.decode(fixture.compact, Limits.default())
    end

    assert_error_code(PartyDescriptor.decode(genesis.compact, :bad), :invalid_type)
    assert_error_code(PartyDescriptor.verify(genesis.compact, nil, :bad), :invalid_type)

    assert_error_code(
      PartyDescriptor.verify(genesis.compact, :forged, Limits.default()),
      :descriptor_chain_invalid
    )

    {:ok, genesis_facts} = PartyDescriptor.verify(genesis.compact, nil, Limits.default())

    assert_error_code(
      PartyDescriptor.verify(genesis.compact, genesis_facts, Limits.default()),
      :descriptor_chain_invalid
    )

    successor = DescriptorFixture.successor(genesis, 2)

    assert_error_code(
      PartyDescriptor.verify(successor.compact, nil, Limits.default()),
      :descriptor_chain_invalid
    )

    forged = %{genesis_facts | descriptor_digest: tagged_zero()}

    assert_error_code(
      PartyDescriptor.verify(successor.compact, forged, Limits.default()),
      :descriptor_chain_invalid
    )

    {:ok, second_facts} =
      PartyDescriptor.verify(successor.compact, genesis_facts, Limits.default())

    third = DescriptorFixture.successor(successor, 3)

    assert {:ok, %{descriptor_number: 3}} =
             PartyDescriptor.verify(third.compact, second_facts, Limits.default())

    tampered_lineage = %{
      second_facts
      | lineage: [tamper_signature(successor.compact), genesis.compact]
    }

    assert_error_code(
      PartyDescriptor.verify(third.compact, tampered_lineage, Limits.default()),
      :descriptor_chain_invalid
    )
  end

  test "invalid caller limits remain typed and unknown critical extensions fail closed" do
    genesis = DescriptorFixture.genesis()
    invalid_limits = %{Limits.default() | max_bytes: -1}

    assert_error_code(
      PartyDescriptor.verify(genesis.compact, nil, invalid_limits),
      :invalid_limits
    )

    {:ok, predecessor} = PartyDescriptor.verify(genesis.compact, nil, Limits.default())

    assert_error_code(
      PartyDescriptor.verify(genesis.compact, predecessor, invalid_limits),
      :invalid_limits
    )

    unknown_critical =
      DescriptorFixture.genesis(
        claims: %{
          "extensions" => %{
            "critical" => %{"urn:example:unknown" => %{}},
            "optional" => %{}
          }
        }
      )

    assert_error_code(
      PartyDescriptor.verify(unknown_critical.compact, nil, Limits.default()),
      :descriptor_invalid
    )
  end

  test "fixture timestamps remain valid beyond single-digit descriptor numbers" do
    fixture = DescriptorFixture.genesis() |> DescriptorFixture.successor(11)

    assert {:ok, descriptor} = PartyDescriptor.decode(fixture.compact, Limits.default())
    assert descriptor.descriptor_number == 11
  end

  defp assert_error(compact, predecessor, code) do
    assert {:error, %Error{code: ^code}} =
             PartyDescriptor.verify(compact, predecessor, Limits.default())
  end

  defp assert_error_code(result, code), do: assert({:error, %Error{code: ^code}} = result)

  defp tamper_signature(compact) do
    [protected, payload, signature] = String.split(compact, ".")
    size = byte_size(signature) - 1
    prefix = binary_part(signature, 0, size)
    last = :binary.last(signature)
    protected <> "." <> payload <> "." <> prefix <> if(last == ?A, do: "B", else: "A")
  end

  defp tagged_zero, do: "sha-256:" <> String.duplicate("A", 43)
end
