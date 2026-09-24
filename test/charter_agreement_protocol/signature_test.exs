defmodule CharterAgreementProtocol.SignatureTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Signature}

  describe "substrate_outcome/3 (the honest-failure decision boundary)" do
    test "an undeclared algorithm returns the named diagnostic, not signature_invalid" do
      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
               Signature.substrate_outcome("ML-DSA-65", false, fn -> raise "must not run" end)
    end

    test "an undeclared algorithm never invokes crypto (the laziness property)" do
      detonator = fn ->
        raise "crypto must not be called when the substrate lacks the algorithm"
      end

      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
               Signature.substrate_outcome("Ed25519", false, detonator)
    end

    test "a declared algorithm that verifies returns ok" do
      assert :ok = Signature.substrate_outcome("ML-DSA-65", true, fn -> true end)
    end

    test "a raising crypto call on a capable substrate is signature_invalid, not a crash" do
      assert {:error, %Error{code: :signature_invalid}} =
               Signature.substrate_outcome("ML-DSA-65", true, fn -> raise "provider blew up" end)
    end

    test "the raise disambiguation is pure in its known-answer verdict" do
      assert {:error, %Error{code: :signature_invalid}} =
               Signature.raise_outcome("ML-DSA-65", true)

      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
               Signature.raise_outcome("ML-DSA-65", false)
    end

    test "a declared algorithm that fails returns signature_invalid" do
      assert {:error, %Error{code: :signature_invalid}} =
               Signature.substrate_outcome("ML-DSA-65", true, fn -> false end)
    end
  end

  describe "verify/4 end to end on this substrate" do
    setup do
      {public_key, private_key} = :crypto.generate_key(:mldsa65, [])
      message = "signature-test"
      signature = :crypto.sign(:mldsa65, :none, message, {:expandedkey, private_key})
      %{public_key: public_key, message: message, signature: signature}
    end

    test "a valid ML-DSA-65 signature verifies", %{public_key: pk, message: m, signature: s} do
      assert :ok = Signature.verify(m, s, pk, "ML-DSA-65")
    end

    test "a corrupt right-length signature fails typed, not by raise", %{
      public_key: pk,
      message: m,
      signature: s
    } do
      flipped = <<:erlang.bxor(:binary.at(s, 0), 255)>>
      corrupt = flipped <> binary_part(s, 1, 3308)

      assert {:error, %Error{code: :signature_invalid}} =
               Signature.verify(m, corrupt, pk, "ML-DSA-65")
    end

    test "a corrupt right-length key fails typed, not by raise", %{
      public_key: pk,
      message: m,
      signature: s
    } do
      corrupt = <<0>> <> binary_part(pk, 1, 1951)

      assert {:error, %Error{code: :signature_invalid}} =
               Signature.verify(m, s, corrupt, "ML-DSA-65")
    end

    test "wrong-length inputs reject before any capability question", %{
      public_key: pk,
      message: m
    } do
      assert {:error, %Error{code: :signature_invalid}} =
               Signature.verify(m, :crypto.strong_rand_bytes(3308), pk, "ML-DSA-65")

      # a WRONG-length key (1951 bytes) rejects on the length check
      assert {:error, %Error{code: :signature_invalid}} =
               Signature.verify(m, <<0::3309*8>>, :crypto.strong_rand_bytes(1951), "ML-DSA-65")
    end
  end
end
