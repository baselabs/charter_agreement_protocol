defmodule CharterAgreementProtocol.Signature do
  @moduledoc """
  CAP never authorizes.

  Strict Ed25519 verification boundary for already-framed protocol bytes.

  Before invoking OTP crypto, this module rejects noncanonical point encodings,
  the complete eight-point torsion set for both the public key and `R`, and
  scalars outside the canonical subgroup-order range. This prevents low-order universal
  forgeries that the raw runtime primitive can accept. The module accepts only
  public verification material. It never signs, selects trust, or authorizes an
  artifact.
  """

  alias CharterAgreementProtocol.Error

  @field_prime 2 ** 255 - 19
  @subgroup_order 2 ** 252 + 27_742_317_777_372_353_535_851_937_790_883_648_493

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

  @doc "Verify one exact message and raw 64-byte signature with a raw Ed25519 public key."
  @spec verify(term(), term(), term()) :: :ok | {:error, Error.t()}
  def verify(message, <<_::512>> = signature, <<_::256>> = public_key) when is_binary(message) do
    if strict_inputs?(signature, public_key) and crypto_supported?() and
         :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519]),
       do: :ok,
       else: invalid()
  end

  def verify(_message, _signature, _public_key), do: invalid()

  defp strict_inputs?(<<r::binary-size(32), s::binary-size(32)>>, public_key) do
    strict_point?(public_key) and strict_point?(r) and
      :binary.decode_unsigned(s, :little) < @subgroup_order
  end

  defp strict_point?(<<prefix::binary-size(31), last>>) do
    encoded = <<prefix::binary, last>>
    y = :binary.decode_unsigned(<<prefix::binary, Bitwise.band(last, 0x7F)>>, :little)
    negative_zero? = Bitwise.band(last, 0x80) != 0 and y in [1, @field_prime - 1]

    y < @field_prime and not negative_zero? and encoded not in @small_order_points
  end

  defp crypto_supported? do
    :eddsa in :crypto.supports(:public_keys) and :ed25519 in :crypto.supports(:curves)
  end

  defp invalid, do: {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}
end
