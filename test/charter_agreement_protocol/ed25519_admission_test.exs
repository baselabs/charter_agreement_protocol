defmodule CharterAgreementProtocol.Ed25519AdmissionTest do
  use ExUnit.Case, async: true
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
    {tx, ty, tz, _} = multiply({x, y, 1, mod(x * y)}, order)
    assert tx == 0 and mod(ty + tz) == 0
  end

  property "generated 32-byte keys agree with Euler and extended-coordinate checks" do
    check all(public <- binary(length: 32), max_runs: 400) do
      assert Signature.valid_key?(public, "Ed25519") == reference_admits?(public)
    end
  end

  test "rejects noncanonical y values and wrong lengths" do
    for y <- @prime..(@prime + 18), sign <- 0..1 do
      refute Signature.valid_key?(<<y + sign * 2 ** 255::little-unsigned-size(256)>>, "Ed25519")
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

  defp reference_admits?(<<encoded::little-unsigned-size(256)>> = public) do
    y = rem(encoded, 2 ** 255)
    sign = div(encoded, 2 ** 255)
    numerator = mod(y * y - 1)
    denominator = mod(@d * y * y + 1)
    square = mod(numerator * power(denominator, @prime - 2))

    if y < @prime and denominator != 0 and (square == 0 or power(square, div(@prime - 1, 2)) == 1) and
         not (square == 0 and sign == 1) do
      {x, y} = reference_point(public)
      {x8, y8, z8, _} = {x, y, 1, mod(x * y)} |> double() |> double() |> double()
      not (x8 == 0 and mod(y8 - z8) == 0)
    else
      false
    end
  end

  defp reference_point(<<encoded::little-unsigned-size(256)>>) do
    y = rem(encoded, 2 ** 255)
    square = mod((y * y - 1) * power(mod(@d * y * y + 1), @prime - 2))
    root = power(square, div(@prime + 3, 8))
    root = if mod(root * root) == square, do: root, else: mod(root * power(2, div(@prime - 1, 4)))
    x = if rem(root, 2) == div(encoded, 2 ** 255), do: root, else: mod(-root)
    {x, y}
  end

  defp double({x, y, z, _t}) do
    a = mod(x * x)
    b = mod(y * y)
    c = mod(2 * z * z)
    d = mod(-a)
    e = mod((x + y) * (x + y) - a - b)
    g = mod(d + b)
    f = mod(g - c)
    h = mod(d - b)
    {mod(e * f), mod(g * h), mod(f * g), mod(e * h)}
  end

  defp add({x1, y1, z1, t1}, {x2, y2, z2, t2}) do
    a = mod((y1 - x1) * (y2 - x2))
    b = mod((y1 + x1) * (y2 + x2))
    c = mod(2 * @d * t1 * t2)
    d = mod(2 * z1 * z2)

    {mod((b - a) * (d - c)), mod((d + c) * (b + a)), mod((d - c) * (d + c)),
     mod((b - a) * (b + a))}
  end

  defp multiply(_point, 0), do: {0, 1, 1, 0}

  defp multiply(point, scalar) do
    half = multiply(double(point), div(scalar, 2))
    if rem(scalar, 2) == 1, do: add(half, point), else: half
  end

  defp mod(value), do: Integer.mod(value, @prime)

  defp power(value, exponent),
    do: :crypto.mod_pow(value, exponent, @prime) |> :binary.decode_unsigned()
end
