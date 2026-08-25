defmodule CharterAgreementProtocol.Examples.VisaForkDemo do
  @moduledoc false

  alias CharterAgreementProtocol.{
    Acceptance,
    Base64Url,
    Canonicalization,
    Digest,
    Limits
  }

  @abp_content_digest "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8"
  @abp_deployment_digest "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"
  @grant_digest "sha-256:5k224cZ_lMI9VoUZ_fYM31ZJAcnJiht0GYEpnhes_ZI"

  def run do
    issuer = descriptor(1, "issuer-key")
    acceptor = descriptor(2, "acceptor-key")
    descriptors = [issuer.compact, acceptor.compact]

    genesis =
      revision(1, "Visa supplier terms\n", issuer, acceptor, %{
        "effective_from" => "2026-08-25T12:00:00Z"
      })

    left =
      revision(2, "Visa supplier terms — USD settlement\n", issuer, acceptor, %{
        "charter_id" => genesis.charter_id,
        "prev_revision_digest" => genesis.digest,
        "effective_from" => "2026-08-25T12:00:01Z"
      })

    right =
      revision(2, "Visa supplier terms — EUR settlement\n", issuer, acceptor, %{
        "charter_id" => genesis.charter_id,
        "prev_revision_digest" => genesis.digest,
        "effective_from" => "2026-08-25T12:00:01Z"
      })

    contested_revisions = [genesis, left, right]

    contested_acceptances =
      Enum.flat_map(contested_revisions, fn one ->
        [acceptance(one, issuer, "issuer"), acceptance(one, acceptor, "acceptor")]
      end)

    {:ok, descriptor_chain} =
      CharterAgreementProtocol.verify_descriptor_chain([issuer.compact], Limits.default())

    issuer_left = verify_acceptance(left, Enum.at(contested_acceptances, 2), descriptor_chain)
    issuer_right = verify_acceptance(right, Enum.at(contested_acceptances, 4), descriptor_chain)
    {:ok, evidence} = Acceptance.equivocation(issuer_left, issuer_right)

    {:ok, contested} =
      verify_chain(contested_revisions, contested_acceptances, descriptors)

    {:ok, :contested} =
      CharterAgreementProtocol.governing_revision(
        contested,
        ~U[2026-08-25 12:00:01Z]
      )

    receipt = receipt(left, issuer)
    {:ok, receipt_facts} =
      CharterAgreementProtocol.verify_receipt(receipt, contested, Limits.default())

    repair =
      revision(3, "Visa supplier terms — countersigned repair\n", issuer, acceptor, %{
        "charter_id" => genesis.charter_id,
        "prev_revision_digest" => left.digest,
        "supersedes" => Enum.sort([left.digest, right.digest]),
        "effective_from" => "2026-08-25T12:00:02Z"
      })

    repair_acceptances = [
      acceptance(repair, issuer, "issuer"),
      acceptance(repair, acceptor, "acceptor")
    ]

    {:ok, repaired} =
      verify_chain(
        contested_revisions ++ [repair],
        contested_acceptances ++ repair_acceptances,
        descriptors
      )

    {:ok, governing_after} =
      CharterAgreementProtocol.governing_revision(repaired, ~U[2026-08-25 12:00:02Z])

    IO.puts("equivocation: evidenced")
    IO.puts("equivocation winner: #{inspect(evidence.winner)}")
    IO.puts("governing before repair: contested")
    IO.puts("receipt chain conflict: #{receipt_facts.chain_conflict}")
    IO.puts("receipt governing match: #{receipt_facts.governing_match}")
    IO.puts("receipt action outcome: #{receipt_facts.outcome}")
    IO.puts("repair countersignatures: #{length(repair_acceptances)}")
    IO.puts("governing after repair: #{governing_after}")
    IO.puts("CAP reports evidence; it does not adjudicate or authorize.")
  end

  defp descriptor(seed_byte, kid) do
    {public, private} =
      :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<seed_byte>>, 32))

    claims = %{
      "protocol_revision" => 1,
      "descriptor_number" => 1,
      "verification_keys" => [
        %{
          "key_id" => kid,
          "algorithm" => "Ed25519",
          "public_key" => Base64Url.encode(public),
          "status" => "active"
        }
      ],
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:00Z"
    }

    {:ok, signing_input} =
      CharterAgreementProtocol.descriptor_signing_input(%{"kid" => kid, "claims" => claims})

    compact = externally_sign(signing_input, private)
    {:ok, decoded} = CharterAgreementProtocol.decode_party_descriptor(compact, Limits.default())

    %{
      compact: compact,
      digest: CharterAgreementProtocol.descriptor_digest(decoded),
      kid: kid,
      private: private
    }
  end

  defp revision(number, legal_text, issuer, acceptor, overrides) do
    claims =
      %{
        "protocol_revision" => 1,
        "revision_number" => number,
        "parties" => [
          %{"party_descriptor_digest" => issuer.digest, "role" => "issuer"},
          %{"party_descriptor_digest" => acceptor.digest, "role" => "acceptor"}
        ],
        "legal_text" => %{
          "content_digest" => tagged(:legal_text, legal_text),
          "media_type" => "text/plain",
          "uri_hint" => "https://example.com/visa-supplier-charter.txt"
        },
        "precedence_declaration" => "legal_text_governs",
        "attribution_declaration" => %{"basis" => "bound_deployments"},
        "termination_rules" => %{"reason_codes" => ["mutual", "breach"]},
        "abp_bindings" => [
          %{
            "party_role" => "issuer",
            "blueprint_id" => "example.demo/echo",
            "release_number" => 1,
            "content_digest" => @abp_content_digest,
            "deployment_digest" => @abp_deployment_digest
          }
        ],
        "receipt_profile" => "com.example.charter/default",
        "extensions" => %{"critical" => %{}, "optional" => %{}}
      }
      |> Map.merge(overrides)

    bytes = canonical!(claims)
    digest = tagged(:charter_revision_content, bytes)

    %{
      bytes: bytes,
      claims: claims,
      digest: digest,
      charter_id: Map.get(claims, "charter_id", digest)
    }
  end

  defp acceptance(revision, descriptor, role) do
    claims = %{
      "protocol_revision" => 1,
      "charter_id" => revision.charter_id,
      "revision_number" => revision.claims["revision_number"],
      "revision_digest" => revision.digest,
      "party_descriptor_digest" => descriptor.digest,
      "party_role" => role,
      "accepted_at" => "2026-08-25T13:00:00Z"
    }

    claims =
      if revision.claims["revision_number"] == 1,
        do: claims,
        else: Map.put(claims, "prev_revision_digest", revision.claims["prev_revision_digest"])

    compact("cap+acceptance", descriptor.kid, claims, descriptor.private)
  end

  defp receipt(revision, issuer) do
    claims = %{
      "protocol_revision" => 1,
      "charter_id" => revision.charter_id,
      "revision_number" => revision.claims["revision_number"],
      "revision_digest" => revision.digest,
      "issuing_party_role" => "issuer",
      "agent_party_role" => "issuer",
      "deployment_digest" => @abp_deployment_digest,
      "grant" => %{
        "scheme" => "bap",
        "id" => "grant-2026-07-27-001",
        "grant_digest" => @grant_digest
      },
      "invocation_id" => "123e4567-e89b-42d3-a456-426614174000",
      "decision" => "accepted",
      "outcome" => "effect_committed",
      "occurred_at" => "2026-08-25T12:00:01Z",
      "recorded_at" => "2026-08-25T12:00:02Z",
      "extensions" => %{"critical" => %{}, "optional" => %{}}
    }

    {:ok, signing_input} =
      CharterAgreementProtocol.receipt_signing_input(%{"kid" => issuer.kid, "claims" => claims})

    externally_sign(signing_input, issuer.private)
  end

  defp verify_acceptance(revision_fixture, compact, descriptor_chain) do
    {:ok, revision} =
      CharterAgreementProtocol.decode_charter_revision(revision_fixture.bytes, Limits.default())

    {:ok, facts} =
      CharterAgreementProtocol.verify_acceptance(
        compact,
        revision,
        descriptor_chain,
        Limits.default()
      )

    facts
  end

  defp verify_chain(revisions, acceptances, descriptors) do
    CharterAgreementProtocol.verify_chain(
      Enum.map(revisions, & &1.bytes),
      acceptances,
      descriptors,
      [],
      Limits.default()
    )
  end

  defp externally_sign(signing_input, private) do
    signature = :crypto.sign(:eddsa, :none, signing_input.message, [private, :ed25519])
    {:ok, compact} = CharterAgreementProtocol.assemble_compact(signing_input, signature)
    compact
  end

  defp compact(typ, kid, claims, private) do
    protected = canonical!(%{"alg" => "EdDSA", "kid" => kid, "typ" => typ})
    payload = canonical!(claims)
    message = Base64Url.encode(protected) <> "." <> Base64Url.encode(payload)
    signature = :crypto.sign(:eddsa, :none, message, [private, :ed25519])
    message <> "." <> Base64Url.encode(signature)
  end

  defp tagged(domain, bytes), do: domain |> Digest.hash(bytes) |> Digest.to_tagged()

  defp canonical!(plain) do
    {:ok, bytes} = Canonicalization.encode(tagged_value(plain))
    bytes
  end

  defp tagged_value(value) when is_map(value),
    do: {:object, Enum.map(value, fn {name, item} -> {name, tagged_value(item)} end)}

  defp tagged_value(value) when is_list(value), do: {:array, Enum.map(value, &tagged_value/1)}
  defp tagged_value(value) when is_binary(value), do: {:string, value}
  defp tagged_value(value) when is_integer(value), do: {:integer, value}
end

CharterAgreementProtocol.Examples.VisaForkDemo.run()
