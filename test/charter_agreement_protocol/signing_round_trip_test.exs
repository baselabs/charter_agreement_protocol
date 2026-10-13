defmodule CharterAgreementProtocol.SigningRoundTripTest do
  use ExUnit.Case, async: true
  alias CharterAgreementProtocol, as: CAP
  alias CharterAgreementProtocol.{Capability, Capability.Profile, Error, Limits, SigningFixture}

  for algorithm <- ["Ed25519", "ML-DSA-65"] do
    test "real prepare sign finish for every kind with #{algorithm}" do
      algorithm = unquote(algorithm)

      if Capability.kat_verifies?(algorithm) do
        world = SigningFixture.world(algorithm)

        {:ok, chain} =
          CAP.verify_chain(
            world.set.revisions,
            world.set.acceptances,
            world.set.descriptors,
            [],
            Limits.default()
          )

        {:ok, revision} = CAP.decode_charter_revision(world.revision.bytes, Limits.default())

        for {kind, context} <- [
              party_descriptor: nil,
              acceptance: world.set,
              termination: world.set,
              receipt: chain,
              receipt: revision
            ] do
          assert {:ok, plan} =
                   CAP.prepare_signing(
                     kind,
                     SigningFixture.input(world, kind),
                     context,
                     Limits.default(),
                     Profile.full()
                   )

          signature = SigningFixture.sign(plan.signing_input.message, world.issuer)
          assert {:ok, compact} = CAP.finish_signing(plan, signature)
          assert String.starts_with?(compact, plan.signing_input.message <> ".")
        end

        {:ok, predecessor} = CAP.verify_descriptor(world.issuer.compact, nil, Limits.default())

        next_claims =
          world.issuer.claims
          |> Map.merge(%{
            "descriptor_number" => 2,
            "party_id" => world.issuer.digest,
            "prev_descriptor_digest" => world.issuer.digest
          })

        input = SigningFixture.input(world, :party_descriptor) |> Map.put("claims", next_claims)

        assert {:error, %Error{code: :descriptor_chain_invalid}} =
                 CAP.prepare_signing(
                   :party_descriptor,
                   input,
                   nil,
                   Limits.default(),
                   Profile.full()
                 )

        assert {:ok, plan} =
                 CAP.prepare_signing(
                   :party_descriptor,
                   input,
                   predecessor,
                   Limits.default(),
                   Profile.full()
                 )

        assert {:ok, _} =
                 CAP.finish_signing(
                   plan,
                   SigningFixture.sign(plan.signing_input.message, world.issuer)
                 )
      end
    end
  end

  test "raised limits cover building and finishing a compact larger than defaults" do
    world = SigningFixture.world("Ed25519")
    {:ok, revision} = CAP.decode_charter_revision(world.revision.bytes, Limits.default())

    input =
      SigningFixture.input(world, :receipt)
      |> put_in(["claims", "extensions", "optional", "com.example/large"], %{
        "items" => List.duplicate(String.duplicate("a", 1000), 1200)
      })

    {:ok, limits} = Limits.new(max_bytes: 4_194_304)

    assert {:error, %Error{code: :signing_input_invalid}} =
             CAP.receipt_signing_input(Map.delete(input, "public_key"))

    assert {:ok, plan} = CAP.prepare_signing(:receipt, input, revision, limits, Profile.full())
    signature = SigningFixture.sign(plan.signing_input.message, world.issuer)

    assert {:error, %Error{code: :signing_input_invalid}} =
             CAP.assemble_compact(plan.signing_input, signature)

    assert {:ok, compact} = CAP.finish_signing(plan, signature)
    assert byte_size(compact) > Limits.default().max_bytes
    deep = Enum.reduce(1..70, %{}, fn _, acc -> %{"x" => acc} end)

    input =
      SigningFixture.input(world, :receipt)
      |> put_in(["claims", "extensions", "optional", "com.example/deep"], deep)

    assert {:error, %Error{code: :signing_input_invalid}} =
             CAP.prepare_signing(:receipt, input, revision, Limits.default(), Profile.full())

    {:ok, limits} = Limits.new(max_depth: 128)
    assert {:ok, plan} = CAP.prepare_signing(:receipt, input, revision, limits, Profile.full())

    assert {:ok, _} =
             CAP.finish_signing(
               plan,
               SigningFixture.sign(plan.signing_input.message, world.issuer)
             )
  end
end
