defmodule CharterAgreementProtocol.SigningSetOracleTest do
  use ExUnit.Case, async: true
  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    Base64Url,
    Capability.Profile,
    Chain,
    CharterRevision,
    Error,
    Limits,
    SigningFixture,
    SigningInput
  }

  test "standalone acceptance can pass while the retained set fails the caller profile or limits" do
    for {id, expected} <- [
          {"signing-set-profile-scope", :algorithm_outside_profile},
          {"signing-strict-set-limits", :limit_exceeded}
        ] do
      input = case_input(id)
      set = set(input["context"]["set"])

      {:ok, facts} =
        Chain.verify(set.revisions, set.acceptances, set.descriptors, [], Limits.default())

      value = value(input)

      {:ok, signing_input, artifact} =
        SigningInput.build(:acceptance, Map.delete(value, "public_key"), Limits.default())

      {:ok, {revision, descriptors}} = Chain.signing_context(:acceptance, artifact, facts)
      compact = sign(signing_input.message, 1)

      {:ok, profile} =
        if expected == :algorithm_outside_profile,
          do: Profile.new(algorithms: ["Ed25519"]),
          else: Profile.new()

      {:ok, limits} =
        if expected == :limit_exceeded, do: Limits.new(max_bytes: 4000), else: Limits.new()

      assert {:ok, _facts} =
               CAP.verify_acceptance(compact, revision, descriptors, limits, profile)

      assert {:error, %Error{code: ^expected}} =
               CAP.prepare_signing(:acceptance, value, set, limits, profile)
    end
  end

  test "an unheld successor passes the old producer and fails preparation with its claims code" do
    input = case_input("signing-unheld-successor")
    set = set(input["context"]["set"])
    value = value(input)
    assert {:ok, _input} = CAP.acceptance_signing_input(Map.delete(value, "public_key"), set)

    assert {:error, %Error{code: :acceptance_claims_mismatch}} =
             CAP.prepare_signing(:acceptance, value, set, Limits.default(), Profile.full())
  end

  test "successor context and descriptor key checks remain additive" do
    input = case_input("signing-successor-without-predecessor")

    assert {:ok, _input} =
             CAP.descriptor_signing_input(input |> value() |> Map.delete("public_key"))

    assert {:error, %Error{code: :descriptor_chain_invalid}} =
             CAP.prepare_signing(
               :party_descriptor,
               value(input),
               nil,
               Limits.default(),
               Profile.full()
             )

    input = case_input("signing-wrong-kid")

    assert {:ok, _input} =
             CAP.descriptor_signing_input(input |> value() |> Map.delete("public_key"))

    assert {:error, %Error{code: :signing_key_mismatch}} =
             CAP.prepare_signing(
               :party_descriptor,
               value(input),
               nil,
               Limits.default(),
               Profile.full()
             )

    input = case_input("signing-small-order-key") |> value()

    input =
      put_in(
        input,
        ["claims", "verification_keys", Access.at(0), "public_key"],
        Base64Url.encode(input["public_key"])
      )

    assert {:ok, signing_input} = CAP.descriptor_signing_input(Map.delete(input, "public_key"))
    compact = signing_input.message <> "." <> Base64Url.encode(<<0::512>>)

    assert {:error, %Error{code: :signature_invalid}} =
             CAP.verify_descriptor(compact, nil, Limits.default())

    assert {:error, %Error{code: :signing_key_invalid}} =
             CAP.prepare_signing(:party_descriptor, input, nil, Limits.default(), Profile.full())
  end

  test "a malformed set keeps the old producer code in preparation" do
    input = case_input("signing-bad-set")
    set = set(input["context"]["set"])
    value = value(input)

    assert {:error, %Error{code: :compact_invalid}} =
             CAP.acceptance_signing_input(Map.delete(value, "public_key"), set)

    assert {:error, %Error{code: :compact_invalid}} =
             CAP.prepare_signing(:acceptance, value, set, Limits.default(), Profile.full())
  end

  test "termination lookup names a missing held descriptor and finish rejects a malformed context" do
    input = case_input("signing-ed25519-termination")
    held = set(input["context"]["set"])

    {:ok, facts} =
      Chain.verify(held.revisions, held.acceptances, held.descriptors, [], Limits.default())

    value = value(input)

    {:ok, _signing_input, artifact} =
      SigningInput.build(:termination, Map.delete(value, "public_key"), Limits.default())

    assert {:error, %Error{code: :termination_claims_mismatch}} =
             Chain.signing_context(:termination, artifact, %{facts | descriptor_chains: []})

    assert {:ok, plan} =
             CAP.prepare_signing(:termination, value, held, Limits.default(), Profile.full())

    [_protected, _payload, encoded] = String.split(sign(plan.signing_input.message, 1), ".")
    {:ok, signature} = Base64Url.decode(encoded)

    assert {:error, %Error{code: :invalid_type}} =
             CAP.finish_signing(%{plan | verify_with: nil}, signature)
  end

  test "revision context keeps floating extension values typed" do
    input = case_input("signing-bare-revision-receipt")

    plain =
      JSON.decode!(input["context"]["revision_text"])
      |> put_in(["extensions", "optional", "com.example/number"], %{
        "value" => 1.5,
        "enabled" => true
      })

    {:ok, revision} =
      CAP.decode_charter_revision(
        SigningFixture.canonical(plain),
        Limits.default()
      )

    assert {:error, %Error{code: :receipt_claims_mismatch}} =
             CAP.prepare_signing(
               :receipt,
               value(input),
               revision,
               Limits.default(),
               Profile.full()
             )
  end

  test "tuple fields keep their types at the corresponding positions" do
    input = case_input("signing-bare-revision-receipt")

    plain =
      JSON.decode!(input["context"]["revision_text"])
      |> put_in(["extensions", "optional", "com.example/types"], %{"enabled" => true})

    {:ok, revision} =
      CAP.decode_charter_revision(SigningFixture.canonical(plain), Limits.default())

    digest = CharterRevision.digest(revision)

    value =
      value(input)
      |> put_in(["claims", "charter_id"], digest)
      |> put_in(["claims", "revision_digest"], digest)

    assert {:ok, _plan} =
             CAP.prepare_signing(:receipt, value, revision, Limits.default(), Profile.full())

    malformed = %{
      revision
      | extensions:
          {:object,
           [
             {"critical", {:object, []}},
             {"optional",
              {:object, [{"com.example/types", {:object, [{"enabled", {:boolean, :bad}}]}}]}}
           ]}
    }

    assert {:error, %Error{code: :receipt_invalid}} =
             CAP.prepare_signing(:receipt, value, malformed, Limits.default(), Profile.full())
  end

  defp value(input),
    do:
      input
      |> Map.take(["kid", "claims", "algorithm"])
      |> Map.put("public_key", Base.url_decode64!(input["public_key"], padding: false))

  defp set(input),
    do:
      struct(CharterAgreementProtocol.ArtifactSet,
        revisions: input["revisions"],
        acceptances: input["acceptances"],
        descriptors: input["descriptors"],
        terminations: input["terminations"]
      )

  defp case_input(id),
    do:
      File.read!("priv/conformance/cases/signing-prepare.json")
      |> :json.decode()
      |> Map.fetch!("cases")
      |> Enum.find(&(&1["id"] == id))
      |> Map.fetch!("input")

  defp sign(message, byte) do
    {_public, private} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))
    message <> "." <> Base64Url.encode(:crypto.sign(:eddsa, :none, message, [private, :ed25519]))
  end
end
