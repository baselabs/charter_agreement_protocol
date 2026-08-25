defmodule CharterAgreementProtocol.CharterRevisionTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.CharterRevisionFixture
  alias CharterAgreementProtocol.{Digest, Error, Limits}

  test "decodes canonical genesis and successor revisions through the facade" do
    genesis = CharterRevisionFixture.genesis()

    assert {:ok, revision} =
             CharterAgreementProtocol.decode_charter_revision(genesis.bytes, Limits.default())

    assert revision.revision_number == 1
    assert revision.charter_id == nil
    assert revision.prev_revision_digest == nil
    assert Enum.map(revision.parties, & &1.role) == ["issuer", "acceptor"]
    assert CharterAgreementProtocol.revision_digest(revision) == genesis.digest

    successor = CharterRevisionFixture.successor(genesis, 2)

    assert {:ok, next} =
             CharterAgreementProtocol.decode_charter_revision(successor.bytes, Limits.default())

    assert next.revision_number == 2
    assert next.charter_id == genesis.digest
    assert next.prev_revision_digest == genesis.digest
  end

  test "legal text content digest is over raw bytes under its own domain" do
    fixture = CharterRevisionFixture.genesis()

    {:ok, revision} =
      CharterAgreementProtocol.decode_charter_revision(fixture.bytes, Limits.default())

    expected = :legal_text |> Digest.hash(fixture.legal_text) |> Digest.to_tagged()
    changed = :legal_text |> Digest.hash(fixture.legal_text <> " ") |> Digest.to_tagged()

    assert revision.legal_text.content_digest == expected
    refute revision.legal_text.content_digest == changed
  end

  test "retains every optional and alternate revision-local declaration" do
    base = CharterRevisionFixture.genesis()

    claims =
      base.claims
      |> put_in(["precedence_declaration"], "machine_terms_govern")
      |> put_in(
        ["attribution_declaration"],
        %{
          "basis" => "legal_text",
          "detail_digest" => CharterRevisionFixture.tagged(:legal_text, "attribution")
        }
      )
      |> put_in(["effective_until"], "2026-08-26T12:00:00Z")
      |> update_in(["legal_text"], &Map.delete(&1, "uri_hint"))

    fixture = CharterRevisionFixture.from_claims(claims, base.legal_text)

    assert {:ok, revision} =
             CharterAgreementProtocol.decode_charter_revision(fixture.bytes, Limits.default())

    assert revision.precedence_declaration == :machine_terms_govern
    assert revision.attribution_declaration.basis == :legal_text
    assert is_binary(revision.attribution_declaration.detail_digest)
    assert revision.legal_text.uri_hint == nil
    assert revision.effective_until != nil
  end

  test "rejects unknown and missing outer or nested members without a precedence default" do
    base = CharterRevisionFixture.genesis()
    [first_party | rest] = base.claims["parties"]

    variants = [
      Map.delete(base.claims, "precedence_declaration"),
      Map.put(base.claims, "unexpected", true),
      Map.put(base.claims, "parties", [Map.put(first_party, "unexpected", true) | rest]),
      put_in(base.claims, ["legal_text", "unexpected"], true),
      put_in(base.claims, ["abp_bindings", Access.at(0), "unexpected"], true)
    ]

    for claims <- variants do
      assert_decode_error(CharterRevisionFixture.from_claims(claims, base.legal_text))
    end
  end

  test "enforces genesis and successor coordinates plus effective interval ordering" do
    genesis = CharterRevisionFixture.genesis()
    successor = CharterRevisionFixture.successor(genesis, 2)

    variants = [
      Map.put(genesis.claims, "charter_id", genesis.digest),
      Map.put(genesis.claims, "prev_revision_digest", genesis.digest),
      Map.delete(successor.claims, "charter_id"),
      Map.delete(successor.claims, "prev_revision_digest"),
      Map.put(genesis.claims, "effective_until", genesis.claims["effective_from"]),
      Map.put(genesis.claims, "effective_until", "2026-08-25T11:59:59Z")
    ]

    for claims <- variants do
      assert_decode_error(CharterRevisionFixture.from_claims(claims, genesis.legal_text))
    end
  end

  test "enforces unique party roles and binding roles while retaining exact ABP identities" do
    base = CharterRevisionFixture.genesis()
    [issuer, acceptor] = base.claims["parties"]

    duplicate_roles = Map.put(base.claims, "parties", [issuer, %{acceptor | "role" => "issuer"}])

    unknown_role =
      put_in(base.claims, ["abp_bindings", Access.at(0), "party_role"], "observer")

    for claims <- [duplicate_roles, unknown_role] do
      assert_decode_error(CharterRevisionFixture.from_claims(claims, base.legal_text))
    end

    assert {:ok, revision} =
             CharterAgreementProtocol.decode_charter_revision(base.bytes, Limits.default())

    [binding] = revision.abp_bindings
    assert binding.blueprint_id == "example.demo/echo"
    assert binding.release_number == 1
    assert binding.content_digest == CharterRevisionFixture.abp_content_digest()
    assert binding.deployment_digest == CharterRevisionFixture.abp_deployment_digest()
  end

  test "enforces reason-code and supersession cardinality and uniqueness" do
    genesis = CharterRevisionFixture.genesis()
    successor = CharterRevisionFixture.successor(genesis, 2)

    variants = [
      put_in(genesis.claims, ["termination_rules", "reason_codes"], []),
      put_in(
        genesis.claims,
        ["termination_rules", "reason_codes"],
        List.duplicate("reason", 65)
      ),
      put_in(genesis.claims, ["termination_rules", "reason_codes"], ["same", "same"]),
      Map.put(successor.claims, "supersedes", List.duplicate(genesis.digest, 9)),
      Map.put(successor.claims, "supersedes", [genesis.digest, genesis.digest])
    ]

    for claims <- variants do
      assert_decode_error(CharterRevisionFixture.from_claims(claims, genesis.legal_text))
    end
  end

  test "rejects a non-string supersession member as a typed error" do
    genesis = CharterRevisionFixture.genesis()
    successor = CharterRevisionFixture.successor(genesis, 2)
    claims = Map.put(successor.claims, "supersedes", [42])

    assert_decode_error(CharterRevisionFixture.from_claims(claims, genesis.legal_text))
  end

  test "rejects supersession on genesis where no prior revision exists" do
    genesis = CharterRevisionFixture.genesis()
    claims = Map.put(genesis.claims, "supersedes", [genesis.digest])

    assert_decode_error(CharterRevisionFixture.from_claims(claims, genesis.legal_text))
  end

  test "rejects malformed digests, identifiers, non-empty critical extensions, and improper inputs" do
    base = CharterRevisionFixture.genesis()

    variants = [
      put_in(base.claims, ["legal_text", "content_digest"], "sha-256:short"),
      put_in(
        base.claims,
        ["parties", Access.at(0), "party_descriptor_digest"],
        "sha-256:" <> String.duplicate("_", 43)
      ),
      put_in(base.claims, ["abp_bindings", Access.at(0), "blueprint_id"], "Bad/ID"),
      Map.put(base.claims, "receipt_profile", "https://example.com/profile"),
      put_in(
        base.claims,
        ["extensions", "critical"],
        %{"com.example.charter/unknown" => %{}}
      )
    ]

    for claims <- variants do
      assert_decode_error(CharterRevisionFixture.from_claims(claims, base.legal_text))
    end

    assert {:error, %Error{code: :invalid_type}} =
             CharterAgreementProtocol.decode_charter_revision(:not_bytes, Limits.default())

    invalid_limits = %{Limits.default() | max_bytes: -1}

    assert {:error, %Error{code: :invalid_limits}} =
             CharterAgreementProtocol.decode_charter_revision(base.bytes, invalid_limits)

    assert {:error, %Error{code: :invalid_type}} =
             CharterAgreementProtocol.decode_charter_revision(base.bytes, %{})

    assert {:error, %Error{code: :non_canonical_bytes}} =
             CharterAgreementProtocol.decode_charter_revision(
               base.bytes <> "\n",
               Limits.default()
             )
  end

  test "rejects non-string, empty, and oversized reason codes" do
    base = CharterRevisionFixture.genesis()

    variants = [
      put_in(base.claims, ["termination_rules", "reason_codes"], [1]),
      put_in(base.claims, ["termination_rules", "reason_codes"], [""]),
      put_in(
        base.claims,
        ["termination_rules", "reason_codes"],
        [String.duplicate("r", 129)]
      )
    ]

    for claims <- variants do
      assert_decode_error(CharterRevisionFixture.from_claims(claims, base.legal_text))
    end
  end

  defp assert_decode_error(fixture) do
    assert {:error, %Error{}} =
             CharterAgreementProtocol.decode_charter_revision(fixture.bytes, Limits.default())
  end
end
