defmodule CharterAgreementProtocol.SigningPrepareCases do
  @moduledoc false
  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}

  def cases do
    ed_set = case_input("receipt-verify", "receipt-signed-governing-match")["chain"]
    ml_set = case_input("chain-verify", "chain-mldsa-mixed-revision")
    ed_receipt = case_input("receipt-verify", "receipt-signed-governing-match")
    ml_receipt = case_input("receipt-verify", "receipt-mldsa65-rev3-valid")
    ed = inputs(ed_set, ed_receipt["compact"], "Ed25519")
    ml = inputs(ml_set, ml_receipt["compact"], "ML-DSA-65")

    positives =
      for {label, inputs} <- [{"ed25519", ed}, {"mldsa65", ml}], {kind, input} <- inputs do
        valid("signing-#{label}-#{kind}", input)
      end

    scoped = scope_input(ed_set)
    large_scope = scope_input(ed_set, true)
    scoped_termination = termination_scope(scoped)
    descriptor = ed["party_descriptor"]
    acceptance = ed["acceptance"]
    receipt = ed["receipt"]
    termination = ed["termination"]

    wrong_key =
      :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<9>>, 32))
      |> elem(0)
      |> Base64Url.encode()

    small_order = Base64Url.encode(<<1, 0::248>>)
    size = byte_size(message(descriptor)) + 1 + 86
    narrow = %{"algorithms" => ["Ed25519"], "revisions" => %{"min" => 1, "max" => 3}}
    [predecessor | _] = ed_set["descriptors"]
    {_, successor} = rotation(ed_set)

    positives ++
      [
        invalid("signing-wrong-kid", Map.put(descriptor, "kid", "other"), "signing_key_mismatch"),
        invalid(
          "signing-wrong-bytes",
          Map.put(descriptor, "public_key", wrong_key),
          "signing_key_mismatch"
        ),
        invalid(
          "signing-acceptance-wrong-key",
          Map.put(acceptance, "public_key", wrong_key),
          "signing_key_mismatch"
        ),
        invalid(
          "signing-termination-wrong-key",
          Map.put(termination, "public_key", wrong_key),
          "signing_key_mismatch"
        ),
        invalid(
          "signing-wrong-algorithm",
          Map.merge(descriptor, %{
            "algorithm" => "ML-DSA-65",
            "public_key" => ml["party_descriptor"]["public_key"],
            "claims" => Map.put(descriptor["claims"], "protocol_revision", 3)
          }),
          "signing_key_mismatch"
        ),
        invalid(
          "signing-short-key",
          Map.put(descriptor, "public_key", "AQ"),
          "signing_key_invalid"
        ),
        invalid(
          "signing-small-order-key",
          Map.put(descriptor, "public_key", small_order),
          "signing_key_invalid"
        ),
        invalid(
          "signing-unknown-algorithm",
          Map.put(descriptor, "algorithm", "other"),
          "signing_input_invalid"
        ),
        valid(
          "signing-final-size-exact",
          Map.put(descriptor, "limits", %{"max_bytes" => size}),
          "exact_bound"
        ),
        invalid(
          "signing-final-size-one-below",
          Map.put(descriptor, "limits", %{"max_bytes" => size - 1}),
          "signing_input_invalid",
          "maximum_plus_one"
        ),
        valid("signing-set-profile-scope", Map.put(scoped, "profile", narrow)),
        valid(
          "signing-termination-counterparty-profile",
          Map.put(scoped_termination, "profile", narrow)
        ),
        invalid(
          "signing-termination-party-profile",
          Map.put(termination, "profile", narrow),
          "algorithm_outside_profile",
          "profile_algorithm_outside"
        ),
        invalid(
          "signing-termination-revision-profile",
          Map.put(scoped_termination, "profile", %{"revisions" => %{"min" => 2, "max" => 3}}),
          "revision_outside_profile",
          "profile_revision_outside"
        ),
        invalid(
          "signing-strict-receipt-limits",
          Map.put(receipt, "limits", %{"max_artifact_set_items" => 1}),
          "limit_exceeded",
          "maximum_plus_one"
        ),
        invalid(
          "signing-unknown-limits-member",
          Map.put(descriptor, "limits", %{"algorithms" => 1}),
          "invalid_limits",
          "invalid_type"
        ),
        invalid(
          "signing-unknown-profile-member",
          Map.put(descriptor, "profile", %{"other" => true}),
          "invalid_profile",
          "invalid_type"
        ),
        invalid(
          "signing-party-chain-profile",
          Map.put(acceptance, "profile", narrow),
          "algorithm_outside_profile",
          "profile_algorithm_outside"
        ),
        invalid(
          "signing-set-revision-profile",
          Map.put(scoped, "profile", %{"revisions" => %{"min" => 2, "max" => 3}}),
          "revision_outside_profile",
          "profile_revision_outside"
        ),
        invalid(
          "signing-receipt-profile-scope",
          Map.put(receipt, "profile", narrow),
          "algorithm_outside_profile",
          "profile_algorithm_outside"
        ),
        invalid(
          "signing-artifact-profile",
          Map.put(descriptor, "profile", %{"algorithms" => ["ML-DSA-65"]}),
          "algorithm_outside_profile",
          "profile_algorithm_outside"
        ),
        invalid(
          "signing-revision-profile",
          Map.put(descriptor, "profile", %{"revisions" => %{"min" => 3, "max" => 3}}),
          "revision_outside_profile",
          "profile_revision_outside"
        ),
        invalid(
          "signing-strict-set-limits",
          Map.put(large_scope, "limits", %{"max_bytes" => 4000}),
          "limit_exceeded",
          "maximum_plus_one"
        ),
        invalid(
          "signing-bad-set",
          put_in(acceptance, ["context", "set", "descriptors"], ["bad"]),
          "compact_invalid",
          "chain_invalid"
        ),
        invalid(
          "signing-acceptance-false-coordinates",
          put_in(acceptance, ["claims", "revision_digest"], tagged("missing")),
          "signing_refused"
        ),
        invalid(
          "signing-termination-not-governing",
          put_in(termination, ["context", "set", "acceptances"], []),
          "signing_refused"
        ),
        valid(
          "signing-successor-with-predecessor",
          Map.put(successor, "context", %{"predecessor_compacts" => [predecessor]})
        ),
        invalid(
          "signing-successor-without-predecessor",
          Map.put(successor, "context", nil),
          "descriptor_chain_invalid",
          "chain_invalid"
        ),
        valid(
          "signing-bare-revision-receipt",
          Map.put(receipt, "context", %{"revision_text" => hd(ed_set["revisions"])}),
          "valid",
          "unnamed"
        ),
        invalid(
          "signing-chain-receipt-no-candidate",
          Map.put(receipt, "kid", "other"),
          "signing_key_mismatch"
        ),
        invalid(
          "signing-receipt-claims",
          put_in(receipt, ["claims", "deployment_digest"], tagged("missing")),
          "receipt_claims_mismatch"
        ),
        invalid(
          "signing-key-before-bad-set",
          acceptance
          |> Map.put("public_key", "AQ")
          |> put_in(["context", "set", "descriptors"], ["bad"]),
          "signing_key_invalid"
        ),
        invalid(
          "signing-profile-before-context",
          descriptor |> Map.put("context", 42) |> Map.put("profile", %{"algorithms" => []}),
          "invalid_profile",
          "invalid_type"
        ),
        invalid(
          "signing-limits-before-profile",
          descriptor
          |> Map.put("limits", %{"max_bytes" => -1})
          |> Map.put("profile", %{"algorithms" => []}),
          "invalid_limits",
          "invalid_type"
        ),
        invalid(
          "signing-build-before-key",
          descriptor |> Map.put("claims", %{}) |> Map.put("public_key", "AQ"),
          "signing_input_invalid"
        )
      ] ++
      malformed_contexts(ed) ++
      unheld_cases(ed_set) ++ two_key_cases(ed_set, receipt) ++ raised_cases(receipt)
  end

  defp scope_input(set, large \\ false) do
    [issuer, acceptor] = set["descriptors"]

    d = %{
      "kind" => "party_descriptor",
      "algorithm" => "Ed25519",
      "kid" => header(issuer)["kid"],
      "claims" => Map.put(payload(issuer), "protocol_revision", 2)
    }

    issuer = sign(d, 1)

    acceptor =
      if large do
        claims =
          payload(acceptor)
          |> put_in(["extensions", "optional", "com.example/large"], %{
            "text" => String.duplicate("x", 7000)
          })

        sign(
          %{
            "kind" => "party_descriptor",
            "algorithm" => "EdDSA",
            "kid" => header(acceptor)["kid"],
            "claims" => claims
          },
          2
        )
      else
        acceptor
      end

    parties = [
      %{
        "role" => "issuer",
        "party_descriptor_digest" =>
          tagged_bytes(:party_descriptor_content, payload_bytes(issuer))
      },
      %{
        "role" => "acceptor",
        "party_descriptor_digest" =>
          tagged_bytes(:party_descriptor_content, payload_bytes(acceptor))
      }
    ]

    revision =
      hd(set["revisions"]) |> :json.decode() |> Map.put("parties", parties) |> canonical()

    set = %{
      set
      | "revisions" => [revision],
        "acceptances" => [],
        "descriptors" => [issuer, acceptor]
    }

    receipt = case_input("receipt-verify", "receipt-signed-governing-match")["compact"]
    inputs(set, receipt, "Ed25519")["acceptance"]
  end

  defp termination_scope(acceptance) do
    set = acceptance["context"]["set"]
    counterparty = Enum.at(set["descriptors"], 1)

    counter =
      acceptance
      |> Map.put("algorithm", "EdDSA")
      |> Map.put("kid", header(counterparty)["kid"])
      |> update_in(
        ["claims"],
        &Map.merge(&1, %{
          "protocol_revision" => 1,
          "party_role" => "acceptor",
          "party_descriptor_digest" =>
            tagged_bytes(:party_descriptor_content, payload_bytes(counterparty))
        })
      )

    set = %{set | "acceptances" => [sign(acceptance, 1), sign(counter, 2)]}
    receipt = case_input("receipt-verify", "receipt-signed-governing-match")["compact"]
    inputs(set, receipt, "Ed25519")["termination"]
  end

  defp inputs(set, receipt, alg) do
    descriptor =
      Enum.find(set["descriptors"], fn compact ->
        header(compact)["kid"] == header(receipt)["kid"]
      end)

    kid = header(receipt)["kid"]
    key = Enum.find(payload(descriptor)["verification_keys"], &(&1["key_id"] == kid))
    revision = hd(set["revisions"]) |> :json.decode()
    digest = tagged_bytes(:charter_revision_content, hd(set["revisions"]))
    descriptor_digest = tagged_bytes(:party_descriptor_content, payload_bytes(descriptor))
    common = %{"kid" => kid, "public_key" => key["public_key"], "algorithm" => alg}
    rev = if alg == "Ed25519", do: 2, else: 3

    a = %{
      "protocol_revision" => rev,
      "charter_id" => digest,
      "revision_number" => 1,
      "revision_digest" => digest,
      "party_descriptor_digest" => descriptor_digest,
      "party_role" => "issuer",
      "accepted_at" => "2026-08-25T11:00:00Z"
    }

    t = %{
      "protocol_revision" => rev,
      "charter_id" => digest,
      "governing_revision_digest" => digest,
      "party_descriptor_digest" => descriptor_digest,
      "party_role" => "issuer",
      "reason_code" => hd(revision["termination_rules"]["reason_codes"]),
      "effective_at" => "2026-08-25T12:00:00Z",
      "issued_at" => "2026-08-25T11:59:00Z"
    }

    %{
      "party_descriptor" =>
        Map.merge(common, %{
          "kind" => "party_descriptor",
          "claims" => Map.put(payload(descriptor), "protocol_revision", rev),
          "context" => nil
        }),
      "acceptance" =>
        Map.merge(common, %{"kind" => "acceptance", "claims" => a, "context" => %{"set" => set}}),
      "termination" =>
        Map.merge(common, %{"kind" => "termination", "claims" => t, "context" => %{"set" => set}}),
      "receipt" =>
        Map.merge(common, %{
          "kind" => "receipt",
          "claims" => Map.put(payload(receipt), "protocol_revision", rev),
          "context" => %{"chain" => set}
        })
    }
  end

  defp malformed_contexts(inputs) do
    for {kind, input} <- inputs,
        {suffix, context} <- [{"null", nil}, {"integer", 42}, {"array", []}, {"object", %{}}],
        not (kind == "party_descriptor" and context == nil) do
      invalid(
        "signing-#{kind}-context-#{suffix}",
        Map.put(input, "context", context),
        "invalid_type",
        "invalid_type"
      )
    end
  end

  defp rotation(set) do
    predecessor = hd(set["descriptors"])
    claims = payload(predecessor)
    digest = tagged_bytes(:party_descriptor_content, payload_bytes(predecessor))
    {public, _private} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<5>>, 32))
    [old] = claims["verification_keys"]

    next_claims =
      Map.merge(claims, %{
        "protocol_revision" => 2,
        "descriptor_number" => 2,
        "party_id" => digest,
        "prev_descriptor_digest" => digest,
        "verification_keys" => [%{old | "public_key" => Base64Url.encode(public)}]
      })

    input = %{
      "kind" => "party_descriptor",
      "kid" => old["key_id"],
      "claims" => next_claims,
      "public_key" => old["public_key"],
      "algorithm" => "Ed25519",
      "context" => nil
    }

    {sign(input, 1), input}
  end

  defp unheld_cases(set) do
    {d2, successor} = rotation(set)
    d1 = hd(set["descriptors"])
    d2_digest = tagged_bytes(:party_descriptor_content, payload_bytes(d2))

    d3_claims =
      Map.merge(successor["claims"], %{
        "descriptor_number" => 3,
        "prev_descriptor_digest" => d2_digest
      })

    d3_digest = tagged_bytes(:party_descriptor_content, canonical(d3_claims))
    r1 = hd(set["revisions"])
    r1_digest = tagged_bytes(:charter_revision_content, r1)

    r2 =
      r1
      |> :json.decode()
      |> Map.merge(%{
        "revision_number" => 2,
        "charter_id" => r1_digest,
        "prev_revision_digest" => r1_digest
      })
      |> update_in(["parties"], fn parties ->
        Enum.map(parties, fn p ->
          if p["role"] == "issuer", do: Map.put(p, "party_descriptor_digest", d3_digest), else: p
        end)
      end)
      |> canonical()

    r2_digest = tagged_bytes(:charter_revision_content, r2)

    ctx = %{
      "set" => %{
        set
        | "revisions" => [r1, r2],
          "descriptors" => [d1, d2, Enum.at(set["descriptors"], 1)]
      }
    }

    receipt = case_input("receipt-verify", "receipt-signed-governing-match")["compact"]
    base = inputs(set, receipt, "Ed25519")

    a =
      base["acceptance"]
      |> Map.put("context", ctx)
      |> update_in(
        ["claims"],
        &Map.merge(&1, %{
          "revision_number" => 2,
          "revision_digest" => r2_digest,
          "prev_revision_digest" => r1_digest,
          "party_descriptor_digest" => d3_digest
        })
      )

    # The proposed second revision is unheld by its claimed descriptor history.
    t =
      base["termination"]
      |> Map.put("context", ctx)
      |> put_in(["claims", "party_descriptor_digest"], d3_digest)

    [
      invalid("signing-unheld-successor", a, "acceptance_claims_mismatch"),
      invalid("signing-unheld-termination-refusal", t, "signing_refused")
    ]
  end

  defp two_key_cases(set, receipt) do
    {d2, _successor} = rotation(set)
    r1 = hd(set["revisions"])
    r1_digest = tagged_bytes(:charter_revision_content, r1)
    d2_digest = tagged_bytes(:party_descriptor_content, payload_bytes(d2))

    r2 =
      r1
      |> :json.decode()
      |> Map.merge(%{
        "revision_number" => 2,
        "charter_id" => r1_digest,
        "prev_revision_digest" => r1_digest
      })
      |> update_in(["parties"], fn parties ->
        Enum.map(parties, fn p ->
          if p["role"] == "issuer", do: Map.put(p, "party_descriptor_digest", d2_digest), else: p
        end)
      end)
      |> canonical()

    r2_digest = tagged_bytes(:charter_revision_content, r2)

    extra =
      for {role, byte, descriptor} <- [
            {"issuer", 5, d2},
            {"acceptor", 2, Enum.at(set["descriptors"], 1)}
          ] do
        key = hd(payload(descriptor)["verification_keys"])

        a = %{
          "kind" => "acceptance",
          "algorithm" => "Ed25519",
          "kid" => key["key_id"],
          "claims" => %{
            "protocol_revision" => 2,
            "charter_id" => r1_digest,
            "revision_number" => 2,
            "revision_digest" => r2_digest,
            "prev_revision_digest" => r1_digest,
            "party_descriptor_digest" =>
              tagged_bytes(:party_descriptor_content, payload_bytes(descriptor)),
            "party_role" => role,
            "accepted_at" => "2026-08-25T11:00:00Z"
          }
        }

        sign(a, byte)
      end

    ctx = %{
      "chain" => %{
        set
        | "revisions" => [r1, r2],
          "descriptors" => set["descriptors"] ++ [d2],
          "acceptances" => set["acceptances"] ++ extra
      }
    }

    unknown =
      receipt
      |> Map.put("context", ctx)
      |> put_in(["claims", "revision_digest"], tagged("unknown"))
      |> put_in(["claims", "revision_number"], 3)

    new_key = hd(payload(d2)["verification_keys"])["public_key"]

    [
      valid("signing-two-key-receipt-first", unknown),
      valid("signing-two-key-receipt-second", Map.put(unknown, "public_key", new_key))
    ]
  end

  defp raised_cases(receipt) do
    text =
      receipt
      |> put_in(["claims", "extensions", "optional", "com.example/text"], %{
        "value" => String.duplicate("a", 70_000)
      })

    [
      valid(
        "signing-raised-string-limits",
        Map.put(text, "limits", %{"max_string_bytes" => 100_000})
      )
    ]
  end

  defp valid(id, input, class \\ "valid", key \\ "matched") do
    [protected, payload] = String.split(message(input), ".")

    one(id, class, input, %{
      "status" => "valid",
      "output" => %{"protected_segment" => protected, "payload_segment" => payload, "key" => key}
    })
  end

  defp invalid(id, input, code, class \\ "invalid_constraint"),
    do: one(id, class, input, %{"status" => "invalid", "error_code" => code})

  defp one(id, class, input, expect),
    do: %{
      "id" => id,
      "surface" => "signing.prepare",
      "class" => class,
      "input" => input,
      "expect" => expect
    }

  defp message(input) do
    typ =
      %{
        "party_descriptor" => "cap+party",
        "acceptance" => "cap+acceptance",
        "termination" => "cap+termination",
        "receipt" => "cap+receipt"
      }[input["kind"]]

    Base64Url.encode(
      canonical(%{"alg" => input["algorithm"] || "Ed25519", "kid" => input["kid"], "typ" => typ})
    ) <> "." <> Base64Url.encode(canonical(input["claims"]))
  end

  defp sign(input, byte) do
    {_, private} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))
    message = message(input)
    message <> "." <> Base64Url.encode(:crypto.sign(:eddsa, :none, message, [private, :ed25519]))
  end

  defp tagged(value), do: tagged_bytes(:charter_revision_content, value)
  defp tagged_bytes(domain, bytes), do: domain |> Digest.hash(bytes) |> Digest.to_tagged()

  defp canonical(plain) do
    {:ok, value} = Canonicalization.from_plain(plain)
    {:ok, bytes} = Canonicalization.encode(value)
    bytes
  end

  defp header(compact),
    do: compact |> String.split(".") |> hd() |> Base64Url.decode() |> elem(1) |> :json.decode()

  defp payload_bytes(compact),
    do: compact |> String.split(".") |> Enum.at(1) |> Base64Url.decode() |> elem(1)

  defp payload(compact), do: compact |> payload_bytes() |> :json.decode()

  defp case_input(file, id),
    do:
      File.read!("priv/conformance/cases/#{file}.json")
      |> :json.decode()
      |> Map.fetch!("cases")
      |> Enum.find(&(&1["id"] == id))
      |> Map.fetch!("input")
end
