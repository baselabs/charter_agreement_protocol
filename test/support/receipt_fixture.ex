defmodule CharterAgreementProtocol.ReceiptFixture do
  @moduledoc false

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}

  @grant_vector "../../deps/bounded_authority_protocol/priv/conformance/v1/vectors/grant-holder-proof.json"
                |> Path.expand(__DIR__)
                |> File.read!()
                |> :json.decode()
  @grant_ath "5k224cZ_lMI9VoUZ_fYM31ZJAcnJiht0GYEpnhes_ZI"

  def grant_compact, do: get_in(@grant_vector, ["grant", "compact"])
  def grant_ath, do: @grant_ath
  def grant_digest, do: "sha-256:" <> @grant_ath

  def claims(revision, overrides \\ %{}) do
    %{
      "protocol_revision" => 1,
      "charter_id" => revision.charter_id,
      "revision_number" => revision.claims["revision_number"],
      "revision_digest" => revision.digest,
      "issuing_party_role" => "issuer",
      "agent_party_role" => "issuer",
      "deployment_digest" =>
        CharterAgreementProtocol.CharterRevisionFixture.abp_deployment_digest(),
      "grant" => %{
        "scheme" => "bap",
        "id" => "grant-2026-07-27-001",
        "grant_digest" => grant_digest()
      },
      "invocation_id" => "123e4567-e89b-42d3-a456-426614174000",
      "decision" => "accepted",
      "outcome" => "effect_committed",
      "occurred_at" => "2026-08-25T12:00:00Z",
      "recorded_at" => "2026-08-25T12:00:01Z",
      "extensions" => %{"critical" => %{}, "optional" => %{}}
    }
    |> Map.merge(overrides)
  end

  def compact(claims, descriptor, options \\ []) do
    protected =
      Keyword.get(options, :protected, %{
        "alg" => "EdDSA",
        "typ" => "cap+receipt",
        "kid" => descriptor.kid
      })

    payload_bytes = canonical!(claims)
    protected_segment = protected |> canonical!() |> Base64Url.encode()
    payload_segment = Base64Url.encode(payload_bytes)
    message = protected_segment <> "." <> payload_segment
    private_key = Keyword.get(options, :private, descriptor.private)
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])

    message <> "." <> Base64Url.encode(signature)
  end

  def digest(claims),
    do: :receipt_content |> Digest.hash(canonical!(claims)) |> Digest.to_tagged()

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
