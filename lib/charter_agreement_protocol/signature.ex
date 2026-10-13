defmodule CharterAgreementProtocol.Signature do
  @moduledoc """
  CAP never authorizes.

  Strict verification boundary for already-framed protocol bytes.

  Ed25519: before calling OTP crypto, this module requires the exact key and
  signature lengths and strict, canonical encodings of the public key and
  the signature, as the specification's signature section requires.

  ML-DSA: the strictness rule is the registry row's exact public-key and
  signature byte lengths for the named parameter set, checked before OTP
  crypto. Verification is pure ML-DSA with the context fixed to the empty
  string (RFC 9964).

  ## When the runtime cannot verify

  When the runtime does not declare the row's key algorithm, or declares it
  but cannot perform the operation (the call raises and the pinned
  known-answer vector fails too), verification returns the
  implementation-local diagnostic `:algorithm_unsupported_on_substrate`
  instead of a verdict. It means the signature could not be checked. The
  checks that run before it passed, but whether the signature is valid is
  unknown: a forged signature of the right length gets the same diagnostic.
  Never treat it as verified. A wrong-length or malformed input rejects with
  `signature_invalid` first, on every runtime alike.

  The diagnostic is outside the conformance verdict surface and outside
  cross-verifier report identity; it describes one implementation on one
  runtime, not a protocol verdict.

  The module accepts only public verification material. It never signs,
  selects trust, or authorizes an artifact.
  """

  alias CharterAgreementProtocol.{Algorithm, Capability, Error}

  @ed25519_field_prime 2 ** 255 - 19
  @ed25519_subgroup_order 2 ** 252 + 27_742_317_777_372_353_535_851_937_790_883_648_493

  @ed25519_d 37_095_705_934_669_439_343_138_083_508_754_565_189_542_113_879_843_219_016_388_785_533_085_940_283_555
  # A square root of -1 modulo p, equal to 2^((p - 1) / 4) mod p.
  @ed25519_sqrt_minus_one 0x2B8324804FC1DF0B2B4D00993DFBD7A72F431806AD2FE478C4EE1B274A0EA0B0

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

  @doc false
  @spec valid_key?(term(), term()) :: boolean()
  def valid_key?(public_key, alg) when is_binary(public_key) do
    case Algorithm.row_for(alg) do
      %{public_key_bytes: length, key_algorithm: "Ed25519"} ->
        byte_size(public_key) == length and strict_point?(public_key)

      %{public_key_bytes: length} ->
        byte_size(public_key) == length

      _other ->
        false
    end
  end

  def valid_key?(_public_key, _alg), do: false

  defp verify_ed25519(message, signature, public_key, %{
         signature_bytes: signature_bytes,
         key_algorithm: key_algorithm
       }) do
    if is_binary(signature) and byte_size(signature) == signature_bytes and
         valid_key?(public_key, key_algorithm) and
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
         valid_key?(public_key, key_algorithm) do
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

  def substrate_outcome(key_algorithm, true, verify) do
    if verify.(), do: :ok, else: invalid()
  rescue
    # A provider may become unavailable after the cached probe. Check the
    # known-answer vector live to distinguish that failure from bad input.
    _raise -> raise_outcome(key_algorithm, Capability.kat_verifies?(key_algorithm, true))
  end

  @doc false
  @spec raise_outcome(binary(), boolean()) :: {:error, Error.t()}
  def raise_outcome(_key_algorithm, true), do: invalid()
  def raise_outcome(key_algorithm, false), do: unsupported(key_algorithm)

  defp strict_ed25519_inputs?(
         <<r::binary-size(32), s::binary-size(32)>>,
         _public_key
       ) do
    strict_point?(r) and
      :binary.decode_unsigned(s, :little) < @ed25519_subgroup_order
  end

  defp strict_point?(<<prefix::binary-size(31), last>>) do
    y = :binary.decode_unsigned(<<prefix::binary, Bitwise.band(last, 0x7F)>>, :little)
    strict_decoded_point?(y, Bitwise.bsr(last, 7))
  end

  defp strict_decoded_point?(y, sign) when y < @ed25519_field_prime do
    y_squared = field(y * y)
    numerator = field(y_squared - 1)
    denominator = field(@ed25519_d * y_squared + 1)
    # RFC 8032 section 5.1.3 combines inversion and square root in one exponentiation.
    cubed = field(denominator * denominator * denominator)
    seventh = field(cubed * cubed * denominator)

    root =
      field(
        numerator * cubed * power(field(numerator * seventh), div(@ed25519_field_prime - 5, 8))
      )

    root =
      if field(denominator * root * root) == numerator,
        do: root,
        else: field(root * @ed25519_sqrt_minus_one)

    if denominator != 0 and field(denominator * root * root) == numerator and
         not (root == 0 and sign == 1) do
      x = if rem(root, 2) == sign, do: root, else: field(-root)
      {x8, y8, z8} = {x, y, 1} |> double_point() |> double_point() |> double_point()
      not (x8 == 0 and field(y8 - z8) == 0)
    else
      false
    end
  end

  defp strict_decoded_point?(_y, _sign), do: false

  # Homogeneous Edwards coordinates keep the three doublings free of division.
  defp double_point({x, y, z}) do
    x_squared = field(x * x)
    y_squared = field(y * y)
    sum = field(y_squared - x_squared)
    difference = field(sum - 2 * z * z)

    {field(2 * x * y * difference), field(-sum * (x_squared + y_squared)),
     field(sum * difference)}
  end

  defp field(value), do: Integer.mod(value, @ed25519_field_prime)

  defp power(base, exponent) do
    :crypto.mod_pow(base, exponent, @ed25519_field_prime) |> :binary.decode_unsigned()
  rescue
    # Point admission remains deterministic when the native library cannot load.
    _error in [ErlangError, UndefinedFunctionError] -> power_fallback(base, exponent, 1)
  end

  defp power_fallback(_base, 0, result), do: result

  defp power_fallback(base, exponent, result) do
    next = if rem(exponent, 2) == 1, do: field(result * base), else: result
    power_fallback(field(base * base), div(exponent, 2), next)
  end

  defp invalid, do: {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}

  defp unsupported(key_algorithm),
    do: {:error, Error.new(:algorithm_unsupported_on_substrate, ["signature", key_algorithm])}
end
