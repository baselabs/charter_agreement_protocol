defmodule CharterAgreementProtocol.SigningPlanTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol, as: CAP
  alias CharterAgreementProtocol.{Capability.Profile, DescriptorFixture, Error, Limits}

  setup do
    descriptor = DescriptorFixture.genesis()
    [key] = descriptor.claims["verification_keys"]

    input = %{
      "kid" => descriptor.kid,
      "claims" => Map.put(descriptor.claims, "protocol_revision", 2),
      "public_key" => Base.url_decode64!(key["public_key"], padding: false)
    }

    %{descriptor: descriptor, input: input}
  end

  test "prepare and finish a real descriptor", %{descriptor: descriptor, input: input} do
    assert {:ok, plan} =
             CAP.prepare_signing(:party_descriptor, input, nil, Limits.default(), Profile.full())

    assert plan.key == :matched

    signature =
      :crypto.sign(:eddsa, :none, plan.signing_input.message, [descriptor.private, :ed25519])

    assert {:ok, compact} = CAP.finish_signing(plan, signature)
    assert {:ok, _} = CAP.verify_descriptor(compact, nil, Limits.default())
    assert {:error, %Error{code: :signature_invalid}} = CAP.finish_signing(plan, <<0::512>>)
  end

  test "snapshot key shape and membership have separate codes", %{input: input} do
    for {changes, code} <- [
          {%{"public_key" => <<1, 0::248>>}, :signing_key_invalid},
          {%{"public_key" => "short"}, :signing_key_invalid},
          {%{"kid" => "other"}, :signing_key_mismatch},
          {%{"public_key" => elem(:crypto.generate_key(:eddsa, :ed25519, <<9::256>>), 0)},
           :signing_key_mismatch}
        ] do
      assert {:error, %Error{code: ^code}} =
               CAP.prepare_signing(
                 :party_descriptor,
                 Map.merge(input, changes),
                 nil,
                 Limits.default(),
                 Profile.full()
               )
    end
  end

  test "options and context precede building and key shape", %{input: input} do
    assert {:error, %Error{code: :invalid_limits}} =
             CAP.prepare_signing(:receipt, %{}, nil, nil, nil)

    assert {:error, %Error{code: :invalid_profile}} =
             CAP.prepare_signing(:receipt, %{}, nil, Limits.default(), nil)

    assert {:error, %Error{code: :invalid_type}} =
             CAP.prepare_signing(:receipt, input, nil, Limits.default(), Profile.full())

    assert {:error, %Error{code: :signing_input_invalid}} =
             CAP.prepare_signing(:party_descriptor, %{}, nil, Limits.default(), Profile.full())

    assert {:error, %Error{code: :invalid_type}} = CAP.finish_signing(nil, <<>>)
  end
end
