defmodule CharterAgreementProtocol.Ed25519AdmissionTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    Base64Url,
    Capability.Profile,
    DescriptorFixture,
    Error,
    Limits,
    Signature,
    SigningFixture
  }

  @prime 2 ** 255 - 19
  @d 37_095_705_934_669_439_343_138_083_508_754_565_189_542_113_879_843_219_016_388_785_533_085_940_283_555
  @base Base.decode16!("5866666666666666666666666666666666666666666666666666666666666666")
  @mixed Base.decode16!("9599999999999999999999999999999999999999999999999999999999999999")
  @rejected [
    {"identity", "0100000000000000000000000000000000000000000000000000000000000000"},
    {"torsion c717 positive", "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a"},
    {"zero y negative", "0000000000000000000000000000000000000000000000000000000000000080"},
    {"torsion 26e8 positive", "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05"},
    {"order two", "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f"},
    {"torsion 26e8 negative", "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85"},
    {"zero y positive", "0000000000000000000000000000000000000000000000000000000000000000"},
    {"torsion c717 negative", "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa"},
    {"identity negative zero",
     "0100000000000000000000000000000000000000000000000000000000000080"},
    {"order two negative zero",
     "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},
    {"y two has no curve point",
     "0200000000000000000000000000000000000000000000000000000000000000"}
  ]

  for {name, hex} <- @rejected do
    test "rejects #{name} on key admission and signing preparation" do
      public = Base.decode16!(unquote(hex), case: :mixed)
      refute reference_admits?(public)
      refute Signature.valid_key?(public, "Ed25519")
      refute Signature.valid_key?(public, "EdDSA")

      assert {:error, %Error{code: :signing_key_invalid}} =
               CAP.prepare_signing(
                 :party_descriptor,
                 input(public),
                 nil,
                 Limits.default(),
                 Profile.full()
               )
    end
  end

  for {name, hex} <- Enum.take(@rejected, -3) |> Enum.take(2) do
    test "rejects #{name} with R base point and S one" do
      public = Base.decode16!(unquote(hex), case: :mixed)
      request = input(public)

      header =
        SigningFixture.canonical(%{"alg" => "Ed25519", "kid" => "k", "typ" => "cap+party"})

      message =
        Base64Url.encode(header) <>
          "." <> Base64Url.encode(SigningFixture.canonical(request["claims"]))

      signature = @base <> <<1, 0::248>>
      compact = message <> "." <> Base64Url.encode(signature)

      assert {:error, %Error{code: :signature_invalid}} =
               Signature.verify(message, signature, public, "Ed25519")

      assert {:error, %Error{code: :signature_invalid}} =
               CAP.verify_descriptor(compact, nil, Limits.default(), Profile.full())
    end
  end

  test "admits the base point and the base point plus order two" do
    for public <- [@base, @mixed] do
      assert reference_admits?(public)
      assert Signature.valid_key?(public, "Ed25519")

      assert {:ok, %{key: :matched}} =
               CAP.prepare_signing(
                 :party_descriptor,
                 input(public),
                 nil,
                 Limits.default(),
                 Profile.full()
               )
    end

    # Multiplying by the odd subgroup order leaves the order-two component.
    {x, y} = reference_point(@mixed)
    order = 2 ** 252 + 27_742_317_777_372_353_535_851_937_790_883_648_493
    assert multiply({x, y}, order) == {0, @prime - 1}
  end

  property "generated 32-byte keys agree with Tonelli-Shanks and affine addition" do
    check all(public <- binary(length: 32), max_runs: 400) do
      assert Signature.valid_key?(public, "Ed25519") == reference_admits?(public)
    end
  end

  test "key admission uses one native big integer exponentiation" do
    {admitted, calls} =
      CharterAgreementProtocol.CryptoTrace.count(:crypto, :mod_pow, 3, fn ->
        Signature.valid_key?(@base, "Ed25519")
      end)

    assert admitted
    assert length(calls) == 1
    assert [[_base, exponent, prime]] = calls
    assert exponent == div(@prime - 5, 8)
    assert prime == @prime
  end

  test "rejects noncanonical y values and wrong lengths" do
    for y <- @prime..(@prime + 18), sign <- 0..1 do
      public = <<y + sign * 2 ** 255::little-unsigned-size(256)>>
      refute reference_admits?(public)
      refute Signature.valid_key?(public, "Ed25519")
    end

    for key <- [nil, "", <<0::248>>, <<0::264>>], do: refute(Signature.valid_key?(key, "Ed25519"))
  end

  defp input(public) do
    claims = DescriptorFixture.genesis().claims |> Map.put("protocol_revision", 2)

    key = %{
      "key_id" => "k",
      "algorithm" => "Ed25519",
      "public_key" => Base64Url.encode(public),
      "status" => "active"
    }

    %{
      "kid" => "k",
      "algorithm" => "Ed25519",
      "claims" => Map.put(claims, "verification_keys", [key]),
      "public_key" => public
    }
  end

  # This reference uses Tonelli-Shanks, Euclidean inversion and affine addition.
  defp reference_admits?(public) do
    case reference_point(public) do
      nil -> false
      point -> multiply(point, 8) != {0, 1}
    end
  end

  defp reference_point(<<encoded::little-unsigned-size(256)>>) do
    y = rem(encoded, 2 ** 255)
    sign = div(encoded, 2 ** 255)
    denominator = mod(@d * y * y + 1)

    if y < @prime and denominator != 0 do
      square = mod((y * y - 1) * inverse(denominator))

      case tonelli(square) do
        nil -> nil
        0 when sign == 1 -> nil
        root -> {if(rem(root, 2) == sign, do: root, else: mod(-root)), y}
      end
    end
  end

  defp tonelli(0), do: 0

  defp tonelli(square) do
    if power(square, div(@prime - 1, 2)) == 1 do
      {q, s} = odd_part(@prime - 1, 0)
      z = Enum.find(2..100, &(power(&1, div(@prime - 1, 2)) == @prime - 1))
      tonelli_loop(s, power(z, q), power(square, q), power(square, div(q + 1, 2)))
    end
  end

  defp odd_part(q, s) when rem(q, 2) == 0, do: odd_part(div(q, 2), s + 1)
  defp odd_part(q, s), do: {q, s}

  defp tonelli_loop(_m, _c, 1, root), do: root

  defp tonelli_loop(m, c, t, root) do
    i = first_one(t, 0)
    b = power(c, 2 ** (m - i - 1))
    tonelli_loop(i, mod(b * b), mod(t * b * b), mod(root * b))
  end

  defp first_one(1, i), do: i
  defp first_one(t, i), do: first_one(mod(t * t), i + 1)

  defp add({x1, y1}, {x2, y2}) do
    k = mod(@d * x1 * x2 * y1 * y2)

    {mod((x1 * y2 + y1 * x2) * inverse(mod(1 + k))),
     mod((y1 * y2 + x1 * x2) * inverse(mod(1 - k)))}
  end

  defp multiply(_point, 0), do: {0, 1}

  defp multiply(point, scalar) do
    half = multiply(add(point, point), div(scalar, 2))
    if rem(scalar, 2) == 1, do: add(half, point), else: half
  end

  defp inverse(value), do: euclid(value, @prime, 1, 0)
  defp euclid(1, _other, coefficient, _previous), do: mod(coefficient)

  defp euclid(value, other, coefficient, previous),
    do: euclid(rem(other, value), value, previous - div(other, value) * coefficient, coefficient)

  defp mod(value), do: Integer.mod(value, @prime)

  defp power(value, exponent),
    do: :crypto.mod_pow(value, exponent, @prime) |> :binary.decode_unsigned()
end
