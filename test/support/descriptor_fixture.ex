defmodule CharterAgreementProtocol.DescriptorFixture do
  @moduledoc false

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}

  def key(byte, key_id, status \\ "active") do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))

    {%{
       "key_id" => key_id,
       "algorithm" => "Ed25519",
       "public_key" => Base64Url.encode(public),
       "status" => status
     }, private}
  end

  def genesis(options \\ []) do
    {key, private} = Keyword.get_lazy(options, :key, fn -> key(1, "genesis-key") end)

    claims =
      %{
        "protocol_revision" => 1,
        "descriptor_number" => 1,
        "verification_keys" => [key],
        "attestation_hints" => [],
        "extensions" => %{"critical" => %{}, "optional" => %{}},
        "effective_from" => "2026-08-25T10:00:00Z"
      }
      |> Map.merge(Keyword.get(options, :claims, %{}))

    compact(claims, Keyword.get(options, :kid, key["key_id"]), private, options)
  end

  def successor(predecessor, number, options \\ []) do
    {key, own_private} = Keyword.get_lazy(options, :key, fn -> key(number, "key-#{number}") end)
    signing_private = Keyword.get(options, :signing_private, predecessor.private)
    signing_kid = Keyword.get(options, :kid, predecessor.kid)

    claims =
      %{
        "protocol_revision" => 1,
        "party_id" => predecessor.party_id,
        "descriptor_number" => number,
        "prev_descriptor_digest" => predecessor.digest,
        "verification_keys" => [key],
        "attestation_hints" => [],
        "extensions" => %{"critical" => %{}, "optional" => %{}},
        "effective_from" => "2026-08-25T10:00:0#{number - 1}Z"
      }
      |> Map.merge(Keyword.get(options, :claims, %{}))

    compact(
      claims,
      signing_kid,
      signing_private,
      Keyword.merge(options,
        private: own_private,
        own_kid: key["key_id"],
        party_id: predecessor.party_id
      )
    )
  end

  def compact(claims, kid, signing_private, options \\ []) do
    protected =
      Keyword.get(options, :protected, %{"alg" => "EdDSA", "typ" => "cap+party", "kid" => kid})

    payload_bytes = canonical!(claims)
    protected_bytes = canonical!(protected)
    protected_segment = Base64Url.encode(protected_bytes)
    payload_segment = Base64Url.encode(payload_bytes)
    message = protected_segment <> "." <> payload_segment
    signature = :crypto.sign(:eddsa, :none, message, [signing_private, :ed25519])
    compact = message <> "." <> Base64Url.encode(signature)
    digest = :party_descriptor_content |> Digest.hash(payload_bytes) |> Digest.to_tagged()

    %{
      compact: compact,
      claims: claims,
      digest: digest,
      party_id: Keyword.get(options, :party_id, digest),
      kid: Keyword.get(options, :own_kid, kid),
      private: Keyword.get(options, :private, signing_private),
      signing_private: signing_private
    }
  end

  defp canonical!(plain) do
    {:ok, bytes} = Canonicalization.encode(tagged(plain))
    bytes
  end

  defp tagged(value) when is_map(value),
    do: {:object, Enum.map(value, fn {name, item} -> {name, tagged(item)} end)}

  defp tagged(value) when is_list(value), do: {:array, Enum.map(value, &tagged/1)}
  defp tagged(value) when is_binary(value), do: {:string, value}
  defp tagged(value) when is_integer(value), do: {:integer, value}
  defp tagged(value) when is_boolean(value), do: {:boolean, value}
end
