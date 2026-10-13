defmodule CharterAgreementProtocol.Ed25519KeyCases do
  @moduledoc false
  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}

  @base Base.decode16!("5866666666666666666666666666666666666666666666666666666666666666")
  @mixed Base.decode16!("9599999999999999999999999999999999999999999999999999999999999999")
  @order 2 ** 252 + 27_742_317_777_372_353_535_851_937_790_883_648_493

  def cases do
    rejected = [
      {"identity-negative-zero",
       "0100000000000000000000000000000000000000000000000000000000000080"},
      {"order-two-negative-zero",
       "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},
      {"no-curve-point", "0200000000000000000000000000000000000000000000000000000000000000"}
    ]

    negatives =
      Enum.flat_map(rejected, fn {name, hex} ->
        public = Base.decode16!(hex, case: :mixed)
        {claims, _challenge} = even_challenge(public)

        [
          descriptor_case(name, claims, @base <> <<1, 0::248>>, invalid("signature_invalid")),
          signing_case(name, public, claims, invalid("signing_key_invalid"))
        ]
      end)

    # This key is B plus the order-two point. Its scalar is one; an even
    # reduced challenge removes the order-two component from verification.
    {claims, challenge} = even_challenge(@mixed)

    signature = @base <> <<rem(1 + challenge, @order)::little-unsigned-size(256)>>
    digest = :party_descriptor_content |> Digest.hash(canonical(claims)) |> Digest.to_tagged()
    output = %{"descriptor_digest" => digest, "party_id" => digest, "descriptor_number" => 1}
    [protected, payload] = String.split(message(claims), ".")

    negatives ++
      [
        descriptor_case("mixed-order", claims, signature, valid(output)),
        signing_case(
          "mixed-order",
          @mixed,
          claims,
          valid(%{
            "protected_segment" => protected,
            "payload_segment" => payload,
            "key" => "matched"
          })
        )
      ]
  end

  defp even_challenge(public) do
    Enum.find_value(0..59, fn second ->
      claims = claims(public, second)

      challenge =
        :crypto.hash(:sha512, @base <> public <> message(claims))
        |> :binary.decode_unsigned(:little)
        |> rem(@order)

      if rem(challenge, 2) == 0, do: {claims, challenge}
    end)
  end

  defp claims(public, second) do
    %{
      "protocol_revision" => 2,
      "descriptor_number" => 1,
      "verification_keys" => [
        %{
          "key_id" => "k",
          "algorithm" => "Ed25519",
          "public_key" => Base64Url.encode(public),
          "status" => "active"
        }
      ],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" =>
        "2026-10-13T00:00:" <> String.pad_leading(Integer.to_string(second), 2, "0") <> "Z"
    }
  end

  defp descriptor_case(name, claims, signature, expected) do
    %{
      "id" => "descriptor-ed25519-#{name}",
      "surface" => "party_descriptor.verify",
      "class" => if(expected["status"] == "valid", do: "valid", else: "signature_invalid"),
      "input" => %{
        "compact" => message(claims) <> "." <> Base64Url.encode(signature),
        "predecessor" => nil
      },
      "expect" => expected
    }
  end

  defp signing_case(name, public, claims, expected) do
    %{
      "id" => "signing-ed25519-#{name}",
      "surface" => "signing.prepare",
      "class" => if(expected["status"] == "valid", do: "valid", else: "invalid_constraint"),
      "input" => %{
        "kind" => "party_descriptor",
        "algorithm" => "Ed25519",
        "kid" => "k",
        "claims" => claims,
        "public_key" => Base64Url.encode(public),
        "context" => nil
      },
      "expect" => expected
    }
  end

  defp message(claims),
    do:
      Base64Url.encode(canonical(%{"alg" => "Ed25519", "kid" => "k", "typ" => "cap+party"})) <>
        "." <> Base64Url.encode(canonical(claims))

  defp canonical(value) do
    {:ok, tagged} = Canonicalization.from_plain(value)
    {:ok, bytes} = Canonicalization.encode(tagged)
    bytes
  end

  defp valid(output), do: %{"status" => "valid", "output" => output}
  defp invalid(code), do: %{"status" => "invalid", "error_code" => code}
end
