defmodule CharterAgreementProtocol.ReceiptInspectionCorpus do
  @moduledoc "Fixture construction for portable receipt evidence. CAP never authorizes."

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, ConformanceFixtureKeys, Digest}

  @floor ~w(tenancy live_policy authority effect_ownership execution billing evaluation_truth legal_validity term_satisfaction view_completeness counterparty_view wall_clock)
  @different "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

  def cases(cases) do
    source = Map.new(cases, &{&1["id"], &1})

    scoped =
      Enum.flat_map(~w(ed25519 mldsa65), fn algorithm ->
        matched = Map.fetch!(source, "signer-scope-receipt-matched-#{algorithm}")
        outside = Map.fetch!(source, "signer-scope-receipt-outside-#{algorithm}")

        unrecognized =
          Map.fetch!(source, "signer-scope-receipt-unverified-unrecognized-revision-#{algorithm}")

        [
          successful("matched-#{algorithm}", matched, "matched", :matches, :match),
          successful("grant-differs-#{algorithm}", outside, "outside", :differs, :match),
          successful("unrecognized-#{algorithm}", unrecognized, "not_verified", :absent, :differs)
        ]
      end)

    matched = Map.fetch!(source, "signer-scope-receipt-matched-ed25519")
    terminated = Map.fetch!(source, "receipt-at-termination-instant")
    contested = Map.fetch!(source, "assignment-receipt-contested-holder")
    invalid_signature = Map.fetch!(source, "receipt-signature-invalid")

    unrecognized =
      Map.fetch!(source, "signer-scope-receipt-unverified-unrecognized-revision-ed25519")

    host =
      resign(matched, fn claims ->
        claims
        |> put_in(["grant", "scheme"], "host")
        |> update_in(["grant"], &Map.delete(&1, "grant_digest"))
        |> put_in(["extensions", "optional", "com.example/audit"], %{
          "note" => "café",
          "values" => [true, nil, 2]
        })
      end)

    different_deployment = resign(unrecognized, &Map.put(&1, "deployment_digest", @different))

    scoped ++
      [
        successful("terminated-ed25519", terminated, "not_required", :matches, :terminated),
        successful("contested-ed25519", contested, "not_required", :matches, :contested),
        successful("host-without-digest-ed25519", host, "matched", :absent, :match),
        successful(
          "different-deployment-ed25519",
          different_deployment,
          "not_verified",
          :absent,
          :different_deployment
        ),
        rejected(
          "bad-grant-digest-ed25519",
          matched["input"],
          "invalid_constraint",
          "digest_encoding_invalid",
          %{"grant_reference" => String.slice(@different, 0, 50) <> "B"}
        ),
        rejected("bad-grant-type-ed25519", matched["input"], "invalid_type", "invalid_type", %{
          "grant_reference" => 42
        }),
        rejected("bad-chain-ed25519", matched["input"], "invalid_type", "invalid_type", %{
          "chain" => nil
        }),
        rejected(
          "bad-signature-ed25519",
          invalid_signature["input"],
          "signature_invalid",
          "signature_invalid",
          %{}
        )
      ]
  end

  defp successful(label, source, scope, reference, governing) do
    input = source["input"]
    [protected, payload, signature] = String.split(input["compact"], ".")
    bytes = decode(payload)
    claims = JSON.decode!(bytes)
    header = protected |> decode() |> JSON.decode!()
    claimed = claims["grant"]["grant_digest"]
    reference = reference(reference, claimed)

    [key] =
      input["chain"]["descriptors"]
      |> Enum.flat_map(fn compact ->
        [_protected, payload, _signature] = String.split(compact, ".")
        payload |> decode() |> JSON.decode!() |> Map.fetch!("verification_keys")
      end)
      |> Enum.filter(&(&1["key_id"] == header["kid"] and &1["status"] == "active"))
      |> Enum.uniq()

    thumbprint = key |> Map.take(~w(algorithm public_key)) |> canonical() |> tagged(:signer_key)

    coordinates =
      Map.take(claims, ~w(charter_id revision_digest revision_number issuing_party_role))

    output = %{
      "signed" => %{
        "protected_segment" => protected,
        "payload_segment" => payload,
        "signature_segment" => signature,
        "protected_segment_digest" => raw(protected),
        "payload_segment_digest" => raw(payload),
        "receipt_digest" => tagged(bytes, :receipt_content)
      },
      "claims" => claims,
      "provenance" =>
        Map.merge(coordinates, %{
          "alg" => header["alg"],
          "signing_key_id" => header["kid"],
          "signer_thumbprint" => thumbprint,
          "scope_status" => scope,
          "revision_status" => if(scope == "not_verified", do: "not_verified", else: "verified")
        }),
      "grant" => grant(claimed, reference),
      "agreement" => agreement(governing, hd(input["chain"]["revisions"])),
      "not_verified" => @floor
    }

    class =
      case governing do
        :contested -> "chain_fork"
        :terminated -> "terminated"
        _governing -> "valid"
      end

    row(label, Map.put(input, "grant_reference", reference), class, %{
      "status" => "valid",
      "output" => output
    })
    |> Map.merge(Map.take(source, ["expect_limited"]))
  end

  defp rejected(label, input, class, code, changes) do
    row(label, Map.merge(input, changes), class, %{"status" => "invalid", "error_code" => code})
  end

  defp row(label, input, class, expect) do
    %{
      "id" => "receipt-inspection-" <> label,
      "surface" => "receipt.inspect",
      "input" => input,
      "class" => class,
      "expect" => expect
    }
  end

  defp reference(:matches, claimed), do: claimed
  defp reference(:differs, _claimed), do: @different
  defp reference(:absent, _claimed), do: nil

  defp grant(claimed, reference) do
    {status, reason} =
      case {claimed, reference} do
        {nil, _reference} -> {"not_verified", "receipt_grant_digest_missing"}
        {_claimed, nil} -> {"not_verified", "grant_reference_missing"}
        {same, same} -> {"matches", nil}
        _different -> {"differs", nil}
      end

    %{
      "status" => status,
      "reason" => reason,
      "claimed_digest" => claimed,
      "reference_digest" => reference
    }
  end

  defp agreement(:terminated, _revision), do: unresolved("no_governing_revision")
  defp agreement(:contested, _revision), do: unresolved("contested_governing_revision")

  defp agreement(governing, revision) do
    fields =
      case governing do
        :match -> []
        :differs -> ~w(revision_digest revision_number)
        :different_deployment -> ~w(deployment_digest revision_digest revision_number)
      end

    %{
      "status" => if(fields == [], do: "matches", else: "differs"),
      "reason" => nil,
      "fields" => fields,
      "governing_revision_digest" => tagged(revision, :charter_revision_content),
      "governing_revision_number" => JSON.decode!(revision)["revision_number"]
    }
  end

  defp unresolved(reason) do
    %{
      "status" => "not_verified",
      "reason" => reason,
      "fields" => [],
      "governing_revision_digest" => nil,
      "governing_revision_number" => nil
    }
  end

  defp resign(source, change) do
    [protected, payload, _signature] = String.split(source["input"]["compact"], ".")
    claims = payload |> decode() |> JSON.decode!() |> change.()
    message = protected <> "." <> Base64Url.encode(canonical(claims))
    {_public, private} = ConformanceFixtureKeys.scope_ed25519("issuer")
    signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])
    put_in(source, ["input", "compact"], message <> "." <> Base64Url.encode(signature))
  end

  defp decode(segment), do: Base.url_decode64!(segment, padding: false)
  defp canonical(value), do: value |> Canonicalization.encode_plain() |> elem(1)
  defp raw(bytes), do: bytes |> Digest.of() |> Digest.to_tagged()
  defp tagged(bytes, domain), do: domain |> Digest.hash(bytes) |> Digest.to_tagged()
end
