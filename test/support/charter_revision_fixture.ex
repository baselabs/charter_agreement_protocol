defmodule CharterAgreementProtocol.CharterRevisionFixture do
  @moduledoc false

  alias CharterAgreementProtocol.{Canonicalization, Digest}

  @abp_content_digest "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8"
  @abp_deployment_digest "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"

  def genesis(options \\ []) do
    legal_text = Keyword.get(options, :legal_text, "Example charter terms\n")

    claims =
      base_claims(legal_text)
      |> Map.merge(Keyword.get(options, :claims, %{}))

    from_claims(claims, legal_text)
  end

  def successor(predecessor, number, options \\ []) do
    legal_text = Keyword.get(options, :legal_text, predecessor.legal_text <> "amended\n")

    claims =
      base_claims(legal_text)
      |> Map.merge(%{
        "charter_id" => predecessor.charter_id,
        "revision_number" => number,
        "prev_revision_digest" => predecessor.digest,
        "effective_from" => timestamp(number)
      })
      |> Map.merge(Keyword.get(options, :claims, %{}))

    from_claims(claims, legal_text, charter_id: predecessor.charter_id)
  end

  def from_claims(claims, legal_text, options \\ []) do
    bytes = canonical!(claims)
    digest = tagged(:charter_revision_content, bytes)

    %{
      bytes: bytes,
      claims: claims,
      digest: digest,
      charter_id: Keyword.get(options, :charter_id, digest),
      legal_text: legal_text
    }
  end

  def base_claims(legal_text) do
    %{
      "protocol_revision" => 1,
      "revision_number" => 1,
      "parties" => [party("issuer"), party("acceptor")],
      "legal_text" => %{
        "content_digest" => tagged(:legal_text, legal_text),
        "media_type" => "text/plain",
        "uri_hint" => "https://example.com/charter.txt"
      },
      "precedence_declaration" => "legal_text_governs",
      "attribution_declaration" => %{"basis" => "bound_deployments"},
      "effective_from" => "2026-08-25T12:00:00Z",
      "termination_rules" => %{"reason_codes" => ["mutual", "breach"]},
      "abp_bindings" => [abp_binding("issuer")],
      "receipt_profile" => "com.example.charter/default",
      "extensions" => %{"critical" => %{}, "optional" => %{}}
    }
  end

  def party(role) do
    %{
      "party_descriptor_digest" => tagged(:party_descriptor_content, "party:" <> role),
      "role" => role
    }
  end

  def abp_binding(role) do
    %{
      "party_role" => role,
      "blueprint_id" => "example.demo/echo",
      "release_number" => 1,
      "content_digest" => @abp_content_digest,
      "deployment_digest" => @abp_deployment_digest
    }
  end

  def abp_content_digest, do: @abp_content_digest
  def abp_deployment_digest, do: @abp_deployment_digest
  def tagged(domain, bytes), do: domain |> Digest.hash(bytes) |> Digest.to_tagged()

  defp timestamp(number) do
    ~U[2026-08-25 12:00:00Z]
    |> DateTime.add(number - 1)
    |> DateTime.to_iso8601()
  end

  defp canonical!(plain) do
    {:ok, bytes} = Canonicalization.encode(tagged_value(plain))
    bytes
  end

  defp tagged_value(value) when is_map(value),
    do: {:object, Enum.map(value, fn {name, item} -> {name, tagged_value(item)} end)}

  defp tagged_value(value) when is_list(value), do: {:array, Enum.map(value, &tagged_value/1)}
  defp tagged_value(value) when is_binary(value), do: {:string, value}
  defp tagged_value(value) when is_integer(value), do: {:integer, value}
  defp tagged_value(value) when is_boolean(value), do: {:boolean, value}
end
