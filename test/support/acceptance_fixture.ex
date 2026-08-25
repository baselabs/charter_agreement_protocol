defmodule CharterAgreementProtocol.AcceptanceFixture do
  @moduledoc false

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}

  def claims(revision, descriptor, role, overrides \\ %{}) do
    revision_number = revision.claims["revision_number"]

    %{
      "protocol_revision" => 1,
      "charter_id" => revision.charter_id,
      "revision_number" => revision_number,
      "revision_digest" => revision.digest,
      "party_descriptor_digest" => descriptor.digest,
      "party_role" => role,
      "accepted_at" => "2026-08-25T13:00:00Z"
    }
    |> maybe_previous(revision_number, revision.claims["prev_revision_digest"])
    |> Map.merge(overrides)
  end

  def compact(claims, descriptor, options \\ []) do
    kid = Keyword.get(options, :kid, descriptor.kid)
    private = Keyword.get(options, :private, descriptor.private)
    typ = Keyword.get(options, :typ, "cap+acceptance")
    payload_bytes = canonical!(claims)
    protected_bytes = canonical!(%{"alg" => "EdDSA", "kid" => kid, "typ" => typ})
    protected_segment = Base64Url.encode(protected_bytes)
    payload_segment = Base64Url.encode(payload_bytes)
    message = protected_segment <> "." <> payload_segment
    signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])

    %{
      compact: message <> "." <> Base64Url.encode(signature),
      claims: claims,
      digest: :acceptance_content |> Digest.hash(payload_bytes) |> Digest.to_tagged()
    }
  end

  defp maybe_previous(claims, 1, _previous), do: claims

  defp maybe_previous(claims, _number, previous),
    do: Map.put(claims, "prev_revision_digest", previous)

  defp canonical!(plain) do
    {:ok, bytes} = Canonicalization.encode(tagged(plain))
    bytes
  end

  defp tagged(value) when is_map(value),
    do: {:object, Enum.map(value, fn {name, item} -> {name, tagged(item)} end)}

  defp tagged(value) when is_list(value), do: {:array, Enum.map(value, &tagged/1)}
  defp tagged(value) when is_binary(value), do: {:string, value}
  defp tagged(value) when is_integer(value), do: {:integer, value}
end
