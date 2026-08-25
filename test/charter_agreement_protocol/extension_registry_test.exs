defmodule CharterAgreementProtocol.ExtensionRegistryTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Digest, ExtensionRegistry, Schema}

  @price_terms "com.example/pricing-indexed"
  @price_observation "com.example/pricing-indexed-observation"

  test "the compiled registry has unique seven-field RFC 2606 example entries" do
    entries = ExtensionRegistry.entries()

    assert Enum.map(entries, & &1.namespace) == [
             @price_terms,
             @price_observation,
             "com.example.charter/default",
             "com.example/identity-vlei",
             "com.example/identity-eidas-qeaa",
             "com.example/retired-profile"
           ]

    assert Enum.all?(entries, fn entry ->
             entry
             |> Map.from_struct()
             |> Map.keys()
             |> Enum.sort() ==
               Enum.sort([
                 :namespace,
                 :owner,
                 :criticality,
                 :state,
                 :schema_digest,
                 :a2a_uri,
                 :promoted_at_revision
               ])
           end)

    assert entries |> Enum.map(& &1.namespace) |> Enum.uniq() ==
             Enum.map(entries, & &1.namespace)

    assert Enum.all?(entries, &String.starts_with?(&1.namespace, "com.example"))
    assert Enum.all?(entries, &String.starts_with?(&1.a2a_uri, "https://example.com/"))
    assert Enum.all?(entries, &(&1.owner == "Example Charter Profiles"))

    assert Enum.find(entries, &(&1.namespace == "com.example.charter/default")).a2a_uri ==
             "https://example.com/charter-profiles/com.example.charter/default"
  end

  test "registry resolution, schemas, and lifecycle data are closed" do
    assert {:ok, terms} = ExtensionRegistry.entry(@price_terms)
    assert terms.criticality == :critical
    assert terms.state == :active
    assert terms.promoted_at_revision == nil
    assert is_binary(terms.schema_digest)

    assert {:ok, observation} = ExtensionRegistry.entry(@price_observation)
    assert observation.criticality == :optional
    assert observation.state == :active
    assert is_binary(observation.schema_digest)

    assert {:ok, attestation} = ExtensionRegistry.entry("com.example/identity-vlei")
    assert attestation.state == :reserved
    assert attestation.schema_digest == nil
    assert ExtensionRegistry.entry("org.invalid/not-registered") == :error

    assert {:ok, retired} = ExtensionRegistry.entry("com.example/retired-profile")
    assert retired.state == :retired
    assert retired.promoted_at_revision == 1

    schemas = ExtensionRegistry.schemas()
    assert %Schema.Definition{} = Map.fetch!(schemas, @price_terms)
    assert %Schema.Definition{} = Map.fetch!(schemas, @price_observation)
    refute Map.has_key?(schemas, "com.example/identity-vlei")
  end

  test "one compiled profile table owns placement and receipt-profile eligibility" do
    assert ExtensionRegistry.placement(@price_terms) == {:ok, :charter_revision}
    assert ExtensionRegistry.placement(@price_observation) == {:ok, :receipt}
    assert ExtensionRegistry.placement("com.example/identity-vlei") == {:ok, :party_descriptor}
    assert ExtensionRegistry.placement("com.example/retired-profile") == {:ok, :charter_revision}
    assert ExtensionRegistry.placement("org.invalid/unknown") == :error

    assert ExtensionRegistry.receipt_profile?(@price_observation)
    assert ExtensionRegistry.receipt_profile?("com.example.charter/default")
    refute ExtensionRegistry.receipt_profile?(@price_terms)
    refute ExtensionRegistry.receipt_profile?("com.example/identity-vlei")
    refute ExtensionRegistry.receipt_profile?("org.invalid/unknown")
  end

  test "promotion records remain compatible with the one supported protocol revision" do
    for entry <- ExtensionRegistry.entries() do
      assert is_nil(entry.promoted_at_revision) or
               (is_integer(entry.promoted_at_revision) and entry.promoted_at_revision == 1 and
                  entry.criticality == :critical)
    end
  end

  test "schema and registry digests bind canonical compiled content" do
    for namespace <- [@price_terms, @price_observation] do
      {:ok, entry} = ExtensionRegistry.entry(namespace)
      definition = Map.fetch!(ExtensionRegistry.schemas(), namespace)

      {:ok, schema_bytes} =
        definition |> Schema.document() |> CharterAgreementProtocol.Canonicalization.encode()

      expected = :extension_schema |> Digest.hash(schema_bytes) |> Digest.to_tagged()
      assert entry.schema_digest == expected
    end

    assert %Digest{} = ExtensionRegistry.digest()
    assert ExtensionRegistry.digest() == ExtensionRegistry.digest()
  end

  test "the indexed-price schema uses the current authoritative ISO 4217 alphabetic list" do
    definition = Map.fetch!(ExtensionRegistry.schemas(), @price_terms)

    for currency <- ["USD", "EUR", "XTS", "XXX"] do
      assert {:ok, _value} = Schema.validate(definition, price_terms(currency))
    end

    for currency <- ["usd", "ZZZ", "US", "USDD"] do
      assert {:error, _error} = Schema.validate(definition, price_terms(currency))
    end

    assert {:ok, _value} =
             definition
             |> Schema.validate(
               price_terms("USD")
               |> delete("floor_amount_minor")
               |> delete("cap_amount_minor")
             )

    assert {:ok, _value} =
             definition
             |> Schema.validate(price_terms("USD") |> delete("floor_amount_minor"))
  end

  defp price_terms(currency) do
    {:object,
     [
       {"currency", {:string, currency}},
       {"base_amount_minor", {:integer, 10_000}},
       {"index",
        {:object,
         [
           {"series_document_digest", {:string, tagged("series")}},
           {"series_id", {:string, "EXAMPLE-CPI"}},
           {"observation_lag_days", {:integer, 2}}
         ]}},
       {"formula", {:string, "index_plus_spread"}},
       {"spread_bps", {:integer, 125}},
       {"floor_amount_minor", {:integer, 9_000}},
       {"cap_amount_minor", {:integer, 12_000}},
       {"tolerance_bps", {:integer, 50}}
     ]}
  end

  defp tagged(bytes), do: :legal_text |> Digest.hash(bytes) |> Digest.to_tagged()

  defp delete({:object, members}, key), do: {:object, List.keydelete(members, key, 0)}
end
