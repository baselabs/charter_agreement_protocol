defmodule CharterAgreementProtocol.DescriptorPublicationCorpus do
  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}

  def cases do
    {first, first_private} = ed25519_key(1)
    {second, second_private} = ed25519_key(2)
    {third, _third_private} = ed25519_key(3)
    {fourth, _fourth_private} = ed25519_key(4)
    retained = %{first | "key_id" => "retained"}
    renamed = %{second | "key_id" => "renamed"}
    retired = %{third | "status" => "retired"}
    keys = [retained, renamed, retired]
    commitment = commitment([retained, renamed])
    signer = {first, first_private}

    current = descriptor([first], signer, nil, %{"next_key_commitment" => commitment})
    next = descriptor(keys, signer, current)
    sibling = descriptor(keys, signer, current, %{"effective_from" => "2026-10-03T00:00:00Z"})
    wrong = descriptor(keys ++ [fourth], signer, current)

    legacy = descriptor([first], signer, nil, %{"protocol_revision" => 2})
    legacy_current = descriptor([second], signer, legacy, %{"protocol_revision" => 2})
    legacy_next = descriptor([third], {second, second_private}, legacy_current)
    same_time =
      descriptor(keys, signer, current, %{"effective_from" => current.claims["effective_from"]})

    legacy_history = [legacy, legacy_current, legacy_next]

    descriptor_cases(current, next, wrong, keys, fourth, signer) ++
      chain_cases(current, next, sibling, wrong) ++
      publication_cases(current, next, sibling, wrong, same_time, legacy_history) ++
      mldsa_cases(second) ++
      [
        signing_case("sign-successor", current, next, nil),
        signing_case("sign-opening-mismatch", current, wrong, "descriptor_commitment_mismatch")
      ]
  end

  defp descriptor_cases(current, next, wrong, [retained | _] = keys, fourth, signer) do
    {first, _private} = signer
    mismatch = "descriptor_commitment_mismatch"
    with_current = [current.compact]
    downgrade = descriptor(keys, signer, current, %{"protocol_revision" => 2})
    alias_key = %{retained | "key_id" => "alias"}
    legacy =
      descriptor([first], signer, nil, %{
        "protocol_revision" => 2,
        "next_key_commitment" => current.claims["next_key_commitment"]
      })

    noncanonical =
      descriptor([first], signer, nil, %{
        "next_key_commitment" => "sha-256:" <> String.duplicate("B", 43)
      })

    [
      descriptor_case(
        "successor",
        next,
        with_current,
        "valid",
        valid(%{
          "descriptor_digest" => next.digest,
          "descriptor_number" => 2,
          "party_id" => current.digest
        })
      ),
      rejected_descriptor(
        "missing-active",
        descriptor([retained], signer, current),
        with_current,
        mismatch
      ),
      rejected_descriptor("extra-active", wrong, with_current, mismatch),
      rejected_descriptor(
        "different-active",
        descriptor([retained, fourth], signer, current),
        with_current,
        mismatch
      ),
      rejected_descriptor("downgrade", downgrade, with_current, mismatch),
      rejected_descriptor(
        "active-material-alias",
        descriptor(keys ++ [alias_key], signer, current),
        with_current,
        "descriptor_invalid"
      ),
      descriptor_case("legacy-member", legacy, [], "unknown_member", invalid("unknown_member")),
      rejected_descriptor("noncanonical-commitment", noncanonical, [], "descriptor_invalid")
    ]
  end

  defp descriptor_case(name, descriptor, predecessors, class, expected) do
    case_entry(
      name,
      "party_descriptor.verify",
      class,
      %{"compact" => descriptor.compact, "predecessor_compacts" => predecessors},
      expected
    )
  end

  defp rejected_descriptor(name, descriptor, predecessors, code),
    do: descriptor_case(name, descriptor, predecessors, "invalid_constraint", invalid(code))

  defp chain_cases(current, next, sibling, wrong) do
    [
      case_entry(
        "chain-fork",
        "descriptor_chain.verify",
        "descriptor_fork",
        %{"compacts" => [current.compact, next.compact, sibling.compact]},
        valid(%{
          "positions" => Map.new([current, next, sibling], &{&1.digest, "contested"}),
          "sibling_descriptors" => Enum.sort([next.digest, sibling.digest]),
          "topology" => "forked"
        })
      ),
      case_entry(
        "chain-opening-mismatch",
        "descriptor_chain.verify",
        "chain_invalid",
        %{"compacts" => [current.compact, wrong.compact]},
        invalid("descriptor_chain_invalid")
      )
    ]
  end

  defp publication_cases(current, next, sibling, wrong, same_time, [root, previous, head]) do
    open = document(current, next, [current, next])
    legacy = document(previous, head, [root, previous, head])
    [current_compact, next_compact] = open["descriptors"]
    [_, _, current_signature] = String.split(current_compact, ".")
    [next_header, next_payload, _] = String.split(next_compact, ".")
    corrupt = [current_compact, Enum.join([next_header, next_payload, current_signature], ".")]
    reversed = [next_compact, current_compact]

    [
      publication("opened", open, "valid", publication_output(open, "opened")),
      publication("legacy-history", legacy, "valid", publication_output(legacy, "not_present")),
      publication(
        "history-profile",
        legacy,
        "profile_revision_outside",
        invalid("revision_outside_profile"),
        %{"profile" => %{"revisions" => %{"min" => 8, "max" => 8}}}
      ),
      publication(
        "document-profile",
        open,
        "profile_revision_outside",
        invalid("revision_outside_profile"),
        %{"profile" => %{"revisions" => %{"min" => 1, "max" => 3}}}
      ),
      publication(
        "algorithm-profile",
        open,
        "profile_algorithm_outside",
        invalid("algorithm_outside_profile"),
        %{"profile" => %{"algorithms" => ["EdDSA"]}}
      ),
      publication("type", 7, "invalid_type", invalid("invalid_type")),
      publication(
        "unknown-member",
        Map.put(open, "extra", true),
        "unknown_member",
        invalid("descriptor_publication_invalid")
      ),
      publication(
        "noncanonical",
        canonical(open) <> " ",
        "non_canonical_bytes",
        invalid("descriptor_publication_invalid")
      ),
      publication("artifact-limit", open, "maximum_plus_one", invalid("limit_exceeded"), %{
        "limits" => %{"max_artifact_set_items" => 1}
      }),
      publication("compact-byte-limit", open, "maximum_plus_one", invalid("limit_exceeded"), %{
        "limits" => %{"max_artifact_set_bytes" => 1700}
      }),
      rejected_publication("wrong-current", %{open | "current_descriptor_digest" => next.digest}),
      rejected_publication("wrong-party", %{open | "party_id" => next.digest}),
      rejected_publication("non-direct", document(root, head, [root, previous, head])),
      rejected_publication("missing-genesis", document(previous, head, [previous, head])),
      rejected_publication("reversed", %{open | "descriptors" => reversed}),
      rejected_publication("duplicate", %{
        open
        | "descriptors" => [current_compact, next_compact, next_compact]
      }),
      publication(
        "corrupt-signature",
        %{open | "descriptors" => corrupt},
        "signature_invalid",
        invalid("signature_invalid")
      ),
      rejected_publication(
        "equal-effective-time",
        document(current, same_time, [current, same_time])
      ),
      rejected_publication("signed-fork", document(current, sibling, [current, next, sibling])),
      publication(
        "opening-mismatch",
        document(current, wrong, [current, wrong]),
        "invalid_constraint",
        invalid("descriptor_commitment_mismatch")
      )
    ]
  end

  defp mldsa_cases(successor_key) do
    # Retain the public key and the two nondeterministic signatures.
    fixture =
      __DIR__
      |> Path.join("descriptor_publication_mldsa_fixture.json")
      |> File.read!()
      |> :json.decode()

    key = %{
      "algorithm" => "ML-DSA-65",
      "key_id" => "pq",
      "public_key" => fixture["public_key"],
      "status" => "active"
    }

    current =
      descriptor([key], {key, fixture["current_signature"]}, nil, %{
        "next_key_commitment" => commitment([successor_key])
      })

    next = descriptor([successor_key], {key, fixture["next_signature"]}, current)
    doc = document(current, next, [current, next])

    [
      publication("mldsa-opening", doc, "valid", publication_output(doc, "opened"))
      |> Map.put("expect_limited", invalid("algorithm_unsupported_on_substrate")),
      publication(
        "mldsa-policy",
        doc,
        "profile_algorithm_outside",
        invalid("algorithm_outside_profile"),
        %{"profile" => %{"algorithms" => ["Ed25519"]}}
      )
    ]
  end

  defp signing_case(name, current, successor, error) do
    [protected, payload, _signature] = String.split(successor.compact, ".")
    [key] = current.claims["verification_keys"]

    input = %{
      "algorithm" => key["algorithm"],
      "claims" => successor.claims,
      "context" => %{"predecessor_compacts" => [current.compact]},
      "kid" => key["key_id"],
      "kind" => "party_descriptor",
      "public_key" => key["public_key"]
    }

    output = %{"protected_segment" => protected, "payload_segment" => payload, "key" => "matched"}
    class = if error, do: "invalid_constraint", else: "valid"
    expected = if error, do: invalid(error), else: valid(output)
    case_entry(name, "signing.prepare", class, input, expected)
  end

  defp publication(name, doc, class, expected, options \\ %{}) do
    text = if is_map(doc), do: canonical(doc), else: doc
    input = Map.put(options, "text", text)
    case_entry(name, "descriptor_publication.verify", class, input, expected)
  end

  defp rejected_publication(name, doc),
    do: publication(name, doc, "invalid_constraint", invalid("descriptor_publication_invalid"))

  defp publication_output(doc, status) do
    digest = reference_digest("descriptor-publication-content", canonical(doc))

    doc
    |> Map.take(~w(party_id current_descriptor_digest next_descriptor_digest))
    |> Map.put("publication_digest", digest)
    |> Map.put("commitment_status", status)
    |> valid()
  end

  defp document(current, next, history) do
    %{
      "protocol_revision" => 8,
      "party_id" => current.party_id,
      "current_descriptor_digest" => current.digest,
      "next_descriptor_digest" => next.digest,
      "descriptors" => Enum.map(history, & &1.compact)
    }
  end

  defp ed25519_key(byte) do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))

    {%{
       "algorithm" => "Ed25519",
       "key_id" => "key-#{byte}",
       "public_key" => Base64Url.encode(public),
       "status" => "active"
     }, private}
  end

  defp descriptor(keys, {key, signature_input}, previous, overrides \\ %{}) do
    number = if previous, do: previous.claims["descriptor_number"] + 1, else: 1

    claims = %{
      "protocol_revision" => 8,
      "descriptor_number" => number,
      "verification_keys" => keys,
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-10-0#{number}T00:00:00Z"
    }

    claims =
      if previous do
        Map.merge(claims, %{
          "party_id" => previous.party_id,
          "prev_descriptor_digest" => previous.digest
        })
      else
        claims
      end

    claims = Map.merge(claims, overrides)
    header = %{"alg" => key["algorithm"], "kid" => key["key_id"], "typ" => "cap+party"}
    protected = canonical(header)
    payload = canonical(claims)
    message = Base64Url.encode(protected) <> "." <> Base64Url.encode(payload)

    signature =
      case key["algorithm"] do
        "Ed25519" ->
          :eddsa
          |> :crypto.sign(:none, message, [signature_input, :ed25519])
          |> Base64Url.encode()

        "ML-DSA-65" ->
          signature_input
      end

    digest = reference_digest("party-descriptor-content", payload)

    %{
      claims: claims,
      compact: message <> "." <> signature,
      digest: digest,
      party_id: if(previous, do: previous.party_id, else: digest)
    }
  end

  defp commitment(keys) do
    keys
    |> Enum.map(fn key ->
      bytes = key |> Map.take(~w(algorithm public_key)) |> canonical()
      reference_digest("signer-key", bytes)
    end)
    |> Enum.sort()
    |> canonical()
    |> then(&reference_digest("descriptor-next-keys", &1))
  end

  defp case_entry(name, surface, class, input, expected),
    do: %{
      "id" => "descriptor-publication-" <> name,
      "surface" => surface,
      "class" => class,
      "input" => input,
      "expect" => expected
    }

  defp reference_digest(domain, bytes),
    do: Digest.of(["charter-agreement-protocol/", domain, <<0>>, bytes]) |> Digest.to_tagged()

  defp canonical(plain) do
    {:ok, bytes} = Canonicalization.encode_plain(plain)
    bytes
  end

  defp valid(output), do: %{"status" => "valid", "output" => output}
  defp invalid(code), do: %{"status" => "invalid", "error_code" => code}
end
