defmodule CharterAgreementProtocol.Signature do
  @moduledoc """
  CAP never authorizes.

  Strict verification boundary for already-framed protocol bytes.

  Ed25519: before invoking OTP crypto, this module rejects noncanonical
  point encodings, the complete eight-point torsion set for both the public
  key and `R`, and scalars outside the canonical subgroup-order range. This
  prevents low-order universal forgeries that the raw runtime primitive can
  accept.

  ML-DSA: lattice signatures carry no torsion or point-encoding surface;
  the strictness rule is the registry row's exact public-key and signature
  byte lengths for the named parameterization, enforced before OTP crypto.
  Verification is pure ML-DSA with the context fixed to the empty string
  (RFC 9964).

  ## Substrate honesty

  When the runtime does not declare the row's key algorithm, verification is
  impossible for substrate reasons and fails with the named implementation
  local diagnostic `:algorithm_unsupported_on_substrate` — never conflated
  with `signature_invalid`. The diagnostic fires only after every
  deterministic check has passed and the substrate is the sole obstacle: a
  wrong-length or malformed input rejects with `signature_invalid` first, on
  every substrate alike, so a forged artifact never earns a retryable
  diagnosis. The diagnostic is outside the conformance verdict surface and
  outside cross-verifier report identity; it is an honesty property of one
  implementation on one substrate, not a protocol verdict.

  The module accepts only public verification material. It never signs,
  selects trust, or authorizes an artifact.
  """

  alias CharterAgreementProtocol.{Algorithm, Capability, Error}

  @ed25519_field_prime 2 ** 255 - 19
  @ed25519_subgroup_order 2 ** 252 + 27_742_317_777_372_353_535_851_937_790_883_648_493

  @small_order_points Enum.map(
                        [
                          "0100000000000000000000000000000000000000000000000000000000000000",
                          "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
                          "0000000000000000000000000000000000000000000000000000000000000080",
                          "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
                          "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
                          "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
                          "0000000000000000000000000000000000000000000000000000000000000000",
                          "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa"
                        ],
                        &Base.decode16!(&1, case: :mixed)
                      )

  @ml_dsa_crypto %{
    "ML-DSA-44" => :mldsa44,
    "ML-DSA-65" => :mldsa65,
    "ML-DSA-87" => :mldsa87
  }

  @doc """
  Verify one exact message and signature with a raw public key under the
  registry's key algorithm for `alg`.

  The signature and public-key byte lengths must equal the registry row's
  exact values; anything else rejects before cryptographic work.
  """
  @spec verify(term(), term(), term(), term()) :: :ok | {:error, Error.t()}
  def verify(message, signature, public_key, alg) when is_binary(message) do
    case Algorithm.row_for(alg) do
      %{key_algorithm: "Ed25519"} = row ->
        verify_ed25519(message, signature, public_key, row)

      %{key_algorithm: key_algorithm} = row when is_binary(key_algorithm) ->
        verify_ml_dsa(message, signature, public_key, row, key_algorithm)

      nil ->
        invalid()
    end
  end

  def verify(_message, _signature, _public_key, _alg), do: invalid()

  defp verify_ed25519(message, signature, public_key, %{
         signature_bytes: signature_bytes,
         public_key_bytes: public_key_bytes
       }) do
    if is_binary(signature) and byte_size(signature) == signature_bytes and
         is_binary(public_key) and byte_size(public_key) == public_key_bytes and
         strict_ed25519_inputs?(signature, public_key) do
      substrate_outcome("Ed25519", Capability.declared?("Ed25519"), fn ->
        :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
      end)
    else
      invalid()
    end
  end

  defp verify_ml_dsa(message, signature, public_key, row, key_algorithm) do
    crypto_algorithm = Map.fetch!(@ml_dsa_crypto, key_algorithm)

    if is_binary(signature) and byte_size(signature) == row.signature_bytes and
         is_binary(public_key) and byte_size(public_key) == row.public_key_bytes do
      substrate_outcome(key_algorithm, Capability.declared?(key_algorithm), fn ->
        :crypto.verify(crypto_algorithm, :none, message, signature, public_key)
      end)
    else
      invalid()
    end
  end

  @doc false
  @spec substrate_outcome(binary(), boolean(), (-> boolean())) ::
          :ok | {:error, Error.t()}
  def substrate_outcome(key_algorithm, false, _verify), do: unsupported(key_algorithm)

  def substrate_outcome(_key_algorithm, true, verify) do
    if verify.(), do: :ok, else: invalid()
  end

  defp strict_ed25519_inputs?(
         <<r::binary-size(32), s::binary-size(32)>>,
         public_key
       ) do
    strict_point?(public_key) and strict_point?(r) and
      :binary.decode_unsigned(s, :little) < @ed25519_subgroup_order
  end

  defp strict_point?(<<prefix::binary-size(31), last>>) do
    encoded = <<prefix::binary, last>>
    # Canonical y (< p) plus the complete torsion set covers every noncanonical
    # or low-order encoding, including the negative-zero spellings.
    y = :binary.decode_unsigned(<<prefix::binary, Bitwise.band(last, 0x7F)>>, :little)

    y < @ed25519_field_prime and encoded not in @small_order_points
  end

  defp invalid, do: {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}

  defp unsupported(key_algorithm),
    do: {:error, Error.new(:algorithm_unsupported_on_substrate, ["signature", key_algorithm])}
end
