defmodule CharterAgreementProtocol.ExtensionTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Digest, Error, Extension, ExtensionRegistry}

  @price_terms "com.example/pricing-indexed"
  @price_observation "com.example/pricing-indexed-observation"

  test "a registered critical revision profile validates against its digest-bound schema" do
    envelope = envelope(%{@price_terms => price_terms()}, %{})

    assert {:ok, outcome} = Extension.validate(envelope, :charter_revision)
    assert outcome.critical_extensions == [@price_terms]
    assert outcome.optional_retained == []
    assert outcome.optional_quarantined == []
  end

  test "unknown critical extensions reject while unknown optional bytes are retained and quarantined" do
    unknown = "org.invalid/unknown"
    body = {:object, [{"opaque", {:array, [{:integer, 1}, {:string, "two"}]}}]}

    assert_error(
      Extension.validate(envelope(%{unknown => body}, %{}), :charter_revision),
      :extension_unknown_critical
    )

    assert {:ok, outcome} =
             Extension.validate(envelope(%{}, %{unknown => body}), :charter_revision)

    assert outcome.optional_retained == [unknown]
    assert outcome.optional_quarantined == [unknown]
    assert outcome.retained_bodies == [{unknown, body}]
  end

  test "the envelope is exact, bounded, namespace-safe, and positionally unique" do
    malformed = [
      {:object, [{"critical", {:object, []}}]},
      {:object, [{"optional", {:object, []}}]},
      {:object,
       [
         {"critical", {:object, []}},
         {"optional", {:object, []}},
         {"extra", {:object, []}}
       ]},
      {:object, [{"critical", :null}, {"optional", {:object, []}}]},
      {:array, []}
    ]

    for value <- malformed do
      assert {:error, %Error{}} = Extension.validate(value, :charter_revision)
    end

    reversed =
      {:object, [{"optional", {:object, []}}, {"critical", {:object, []}}]}

    assert {:ok, _outcome} = Extension.validate(reversed, :charter_revision)
    assert {:error, %Error{code: :invalid_type}} = Extension.validate(reversed, :other)
    assert {:error, %Error{code: :invalid_type}} = Extension.validate(reversed, :receipt, 0)

    malformed_entry =
      {:object, [{"critical", {:object, []}}, {"optional", {:object, [:not_a_pair]}}]}

    assert_error(
      Extension.validate(malformed_entry, :charter_revision),
      :extension_namespace_invalid
    )

    assert_error(
      Extension.validate(envelope(%{}, %{"Bad/namespace" => :null}), :charter_revision),
      :extension_namespace_invalid
    )

    duplicate =
      {:object,
       [
         {"critical", {:object, [{@price_terms, price_terms()}]}},
         {"optional", {:object, [{@price_terms, :null}]}}
       ]}

    assert_error(Extension.validate(duplicate, :charter_revision), :extension_duplicate)

    optional =
      1..33
      |> Enum.map(fn number -> {"com.example/unknown-#{number}", :null} end)
      |> then(&{:object, &1})

    assert {:error, %Error{code: :cardinality_violation}} =
             Extension.validate(
               {:object, [{"critical", {:object, []}}, {"optional", optional}]},
               :charter_revision
             )
  end

  test "criticality, artifact placement, schema availability, and schema digest fail closed" do
    assert_error(
      Extension.validate(envelope(%{}, %{@price_terms => price_terms()}), :charter_revision),
      :extension_criticality_conflict
    )

    assert_error(
      Extension.validate(envelope(%{@price_terms => price_terms()}, %{}), :party_descriptor),
      :extension_scope_invalid
    )

    assert_error(
      Extension.validate(
        envelope(%{@price_terms => price_terms()}, %{}),
        :charter_revision,
        %{}
      ),
      :extension_schema_unavailable
    )

    wrong_schema = %{@price_terms => Map.fetch!(ExtensionRegistry.schemas(), @price_observation)}

    assert_error(
      Extension.validate(
        envelope(%{@price_terms => price_terms()}, %{}),
        :charter_revision,
        wrong_schema
      ),
      :extension_schema_digest_mismatch
    )
  end

  test "invalid indexed terms and receipt observations are rejected by their closed schemas" do
    invalid_terms = [
      put(price_terms(), "formula", {:string, "other"}),
      put(price_terms(), "spread_bps", {:integer, 10_001}),
      put(price_terms(), "tolerance_bps", {:integer, -1}),
      put(price_terms(), "cap_amount_minor", {:integer, 8_999}),
      put_in_nested(price_terms(), "index", "observation_lag_days", {:integer, 91}),
      put_in_nested(price_terms(), "index", "series_id", {:string, String.duplicate("x", 129)})
    ]

    for terms <- invalid_terms do
      assert {:error, %Error{}} =
               Extension.validate(envelope(%{@price_terms => terms}, %{}), :charter_revision)
    end

    assert {:ok, outcome} =
             Extension.validate(
               envelope(%{}, %{@price_observation => price_observation()}),
               :receipt
             )

    assert outcome.optional_retained == [@price_observation]
    assert outcome.optional_quarantined == []

    invalid_observation = put(price_observation(), "observation_instant", {:string, "not-time"})

    assert {:error, %Error{}} =
             Extension.validate(
               envelope(%{}, %{@price_observation => invalid_observation}),
               :receipt
             )
  end

  test "reserved attestation names retain opaque optional bodies but cannot become critical" do
    namespace = "com.example/identity-vlei"
    body = {:object, [{"opaque", {:string, "not interpreted"}}]}

    assert {:ok, outcome} =
             Extension.validate(envelope(%{}, %{namespace => body}), :party_descriptor)

    assert outcome.optional_retained == [namespace]
    assert outcome.optional_quarantined == [namespace]

    assert_error(
      Extension.validate(envelope(%{namespace => body}, %{}), :party_descriptor),
      :extension_unknown_critical
    )
  end

  test "retired namespaces cannot become critical and schema-less active bodies fail closed" do
    assert_error(
      Extension.validate(
        envelope(%{"com.example/retired-profile" => :null}, %{}),
        :charter_revision
      ),
      :extension_retired
    )

    assert_error(
      Extension.validate(
        envelope(%{}, %{"com.example.charter/default" => :null}),
        :receipt
      ),
      :extension_schema_unavailable
    )
  end

  defp envelope(critical, optional) do
    {:object,
     [
       {"critical", {:object, Enum.to_list(critical)}},
       {"optional", {:object, Enum.to_list(optional)}}
     ]}
  end

  defp price_terms do
    {:object,
     [
       {"currency", {:string, "USD"}},
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

  defp price_observation do
    {:object,
     [
       {"observed_index_digest", {:string, tagged("observation")}},
       {"observation_instant", {:string, "2026-08-25T12:00:00Z"}},
       {"computed_amount_minor", {:integer, 10_125}}
     ]}
  end

  defp put({:object, members}, key, value),
    do: {:object, List.keystore(members, key, 0, {key, value})}

  defp put_in_nested({:object, members}, parent, key, value) do
    {^parent, nested} = List.keyfind(members, parent, 0)
    put({:object, members}, parent, put(nested, key, value))
  end

  defp tagged(bytes), do: :legal_text |> Digest.hash(bytes) |> Digest.to_tagged()

  defp assert_error({:error, %Error{code: code}}, code), do: :ok
end
