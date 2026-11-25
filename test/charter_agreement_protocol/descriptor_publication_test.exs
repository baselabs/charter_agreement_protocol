defmodule CharterAgreementProtocol.DescriptorPublicationTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    Capability,
    CompactJws,
    DescriptorPublicationFacts,
    Error,
    Facts,
    Limits
  }

  alias CharterAgreementProtocol.Conformance.{Corpus, Runner}

  test "the Ed25519 publication vectors verify the complete history and pair" do
    cases =
      "priv/conformance/cases/descriptor_publication-verify.json"
      |> File.read!()
      |> JSON.decode!()
      |> Map.fetch!("cases")
      |> Enum.reject(&String.contains?(&1["id"], "mldsa"))

    assert cases != []

    for {one, result} <- Enum.zip(cases, Runner.run(struct(Corpus, cases: cases))) do
      assert result.actual == one["expect"], one["id"]
    end
  end

  test "a commitment refuses a downgrade even when its key set opens" do
    %{"cases" => cases} =
      "priv/conformance/cases/party_descriptor-verify.json" |> File.read!() |> JSON.decode!()

    one = Enum.find(cases, &(&1["id"] == "descriptor-publication-downgrade"))

    assert [%{actual: %{"error_code" => "descriptor_commitment_mismatch"}, agree: true}] =
             Runner.run(struct(Corpus, cases: [one]))
  end

  test "encoding retains the canonical publication and verification returns descriptive facts" do
    text = publication_text("opened")
    limits = Limits.default()
    document = JSON.decode!(text)
    assert {:ok, ^text} = CAP.encode_descriptor_publication(document, limits)

    assert {:ok, %DescriptorPublicationFacts{} = facts} =
             CAP.verify_descriptor_publication(text, limits)

    assert facts.canonical_bytes == text
    assert facts.publication_digest == CAP.descriptor_publication_digest(text)
    assert facts.commitment_status == :opened
    assert facts.current_descriptor.descriptor_number == 1
    assert facts.next_descriptor.descriptor_number == 2
    assert facts.not_verified == Facts.not_verified_floor()
    assert inspect(facts) == "#CharterAgreementProtocol.DescriptorPublicationFacts<redacted>"

    float_revision = Map.put(document, "protocol_revision", 8.0)

    assert {:error, %Error{code: :invalid_type}} =
             CAP.encode_descriptor_publication(float_revision, limits)

    empty_compact = Map.put(document, "descriptors", ["", List.last(document["descriptors"])])

    assert {:error, %Error{code: :descriptor_publication_invalid}} =
             CAP.encode_descriptor_publication(empty_compact, limits)
  end

  test "key ids and retired keys are excluded from the complete active key set" do
    %{"descriptors" => [current, next]} = "opened" |> publication_text() |> JSON.decode!()
    limits = Limits.default()
    assert {:ok, current} = CAP.decode_party_descriptor(current, limits)
    assert {:ok, next} = CAP.decode_party_descriptor(next, limits)
    keys = next.verification_keys

    assert {:ok, commitment} = CAP.descriptor_next_key_commitment(keys, limits)
    assert commitment == current.next_key_commitment

    [first, second, retired] = keys
    assert {:ok, ^commitment} = CAP.descriptor_next_key_commitment([second, first], limits)

    assert {:ok, thumbprint} = CAP.signer_thumbprint(first)

    assert {:ok, ^thumbprint} =
             CAP.signer_thumbprint(%{first | key_id: retired.key_id, status: :retired})

    assert {:error, %Error{code: :descriptor_invalid}} =
             CAP.descriptor_next_key_commitment([first, %{first | key_id: "alias"}], limits)

    assert {:error, %Error{code: :nested_invalid}} =
             CAP.descriptor_next_key_commitment([first, %{retired | public_key: <<>>}], limits)
  end

  test "publication encoding and verification enforce caller options at the boundary" do
    limits = Limits.default()
    invalid_limits = %{limits | max_bytes: -1}
    text = publication_text("opened")
    document = JSON.decode!(text)

    assert {:error, %Error{code: :invalid_limits}} =
             CAP.encode_descriptor_publication(document, invalid_limits)

    assert {:error, %Error{code: :invalid_limits}} =
             CAP.verify_descriptor_publication(text, invalid_limits)

    assert {:error, %Error{code: :invalid_profile}} =
             CAP.verify_descriptor_publication(text, limits, nil)

    assert {:error, %Error{code: :invalid_type}} =
             CAP.encode_descriptor_publication(nil, limits)

    assert {:error, %Error{code: :invalid_type}} =
             CAP.encode_descriptor_publication(document, nil)

    assert {:error, %Error{code: :invalid_type}} =
             CAP.verify_descriptor_publication(text, nil)

    assert {:error, %Error{code: :limit_exceeded}} =
             CAP.encode_descriptor_publication(document, %{limits | max_artifact_set_items: 1})

    assert {:error, %Error{code: :limit_exceeded}} =
             CAP.verify_descriptor_publication(text, %{limits | max_bytes: 1})
  end

  test "a publication requires a signed genesis and a successor" do
    limits = Limits.default()
    document = "opened" |> publication_text() |> JSON.decode!()
    broken = %{document | "descriptors" => ["bad", "missing"]}

    assert {:ok, broken_text} = CAP.encode_descriptor_publication(broken, limits)

    assert {:error, %Error{code: :descriptor_chain_invalid}} =
             CAP.verify_descriptor_publication(broken_text, limits)

    profile = Capability.Profile.full()

    assert {:error, %Error{code: :descriptor_publication_invalid}} =
             CAP.PartyDescriptor.verify_publication_history([], limits, profile)
  end

  test "publication coordinates must be tagged digest strings" do
    limits = Limits.default()
    document = "opened" |> publication_text() |> JSON.decode!()
    expected = Error.new(:descriptor_publication_invalid, ["descriptor_publication"])

    for {member, value} <- [
          {"party_id", 1},
          {"current_descriptor_digest", []},
          {"next_descriptor_digest", %{}}
        ] do
      malformed = Map.put(document, member, value)

      assert {:error, ^expected} = CAP.encode_descriptor_publication(malformed, limits)
    end
  end

  test "publication history rejects a signed successor whose predecessor is missing" do
    limits = Limits.default()
    document = "legacy-history" |> publication_text() |> JSON.decode!()
    %{"descriptors" => [genesis, _intermediate, successor]} = document
    incomplete = %{document | "descriptors" => [genesis, successor]}
    expected = Error.new(:descriptor_publication_invalid, ["descriptor_publication"])

    assert {:ok, text} = CAP.encode_descriptor_publication(incomplete, limits)
    assert {:error, ^expected} = CAP.verify_descriptor_publication(text, limits)
  end

  test "publication history returns the signature error from a rejected successor" do
    text = publication_text("corrupt-signature")
    expected = Error.new(:signature_invalid, ["compact_jws", "signature"])

    assert {:error, ^expected} = CAP.verify_descriptor_publication(text, Limits.default())
  end

  test "key commitment options and cardinality fail with typed errors" do
    limits = Limits.default()

    assert {:error, %Error{code: :invalid_type}} =
             CAP.descriptor_next_key_commitment([], nil)

    assert {:error, %Error{code: :invalid_type}} =
             CAP.descriptor_next_key_commitment(nil, limits)

    assert {:error, %Error{code: :invalid_limits}} =
             CAP.descriptor_next_key_commitment([], %{limits | max_bytes: -1})

    assert {:error, %Error{code: :descriptor_invalid}} =
             CAP.descriptor_next_key_commitment(List.duplicate(nil, 33), limits)
  end

  test "signed revision-eight framing admits party artifacts and rejects receipts" do
    %{"descriptors" => [compact | _]} = "opened" |> publication_text() |> JSON.decode!()
    [header, payload, signature] = String.split(compact, ".")
    protected = Base.url_decode64!(header, padding: false)

    for type <- ["cap+acceptance", "cap+termination", "cap+receipt"] do
      changed =
        protected
        |> String.replace("cap+party", type)
        |> Base.url_encode64(padding: false)

      compact = Enum.join([changed, payload, signature], ".")

      case type do
        "cap+receipt" ->
          assert {:error, %Error{code: :protected_header_invalid}} =
                   CompactJws.parse(compact, type, Limits.default())

        _party_artifact ->
          assert {:ok, %CompactJws{typ: ^type}} =
                   CompactJws.parse(compact, type, Limits.default())
      end
    end
  end

  test "ML-DSA history follows the capability lane's certified verdict" do
    text = publication_text("mldsa-opening")
    result = CAP.verify_descriptor_publication(text, Limits.default())

    if Capability.kat_verifies?("ML-DSA-65") do
      assert {:ok, %DescriptorPublicationFacts{commitment_status: :opened}} = result
    else
      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} = result
    end
  end

  defp publication_text(suffix) do
    "priv/conformance/cases/descriptor_publication-verify.json"
    |> File.read!()
    |> JSON.decode!()
    |> Map.fetch!("cases")
    |> Enum.find(&(&1["id"] == "descriptor-publication-" <> suffix))
    |> get_in(["input", "text"])
  end
end
