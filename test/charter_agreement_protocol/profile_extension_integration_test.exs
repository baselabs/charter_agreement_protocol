defmodule CharterAgreementProtocol.ProfileExtensionIntegrationTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    ChainFixture,
    CharterRevisionFixture,
    DescriptorFixture,
    Error,
    Limits,
    Receipt,
    ReceiptFixture
  }

  @price_terms "com.example/pricing-indexed"
  @price_observation "com.example/pricing-indexed-observation"

  test "a revision retains validated indexed-price terms without evaluating them" do
    fixture =
      CharterRevisionFixture.genesis(
        claims: %{
          "extensions" => %{
            "critical" => %{@price_terms => price_terms()},
            "optional" => %{}
          }
        }
      )

    assert {:ok, revision} =
             CharterAgreementProtocol.decode_charter_revision(fixture.bytes, Limits.default())

    assert {:object, regions} = revision.extensions

    assert {"critical", {:object, [{@price_terms, retained}]}} =
             List.keyfind(regions, "critical", 0)

    assert retained != :null
  end

  test "a revision refuses an unregistered receipt-profile namespace" do
    fixture =
      CharterRevisionFixture.genesis(
        claims: %{"receipt_profile" => "com.example/unknown-receipts"}
      )

    assert {:error, %Error{code: :revision_invalid}} =
             CharterAgreementProtocol.decode_charter_revision(fixture.bytes, Limits.default())
  end

  test "profile placement is closed across revision and party artifacts" do
    invalid_revision =
      CharterRevisionFixture.genesis(
        claims: %{
          "extensions" => %{
            "critical" => %{},
            "optional" => %{@price_observation => price_observation()}
          }
        }
      )

    assert {:error, %Error{code: :extension_scope_invalid}} =
             CharterAgreementProtocol.decode_charter_revision(
               invalid_revision.bytes,
               Limits.default()
             )

    descriptor =
      DescriptorFixture.genesis(
        claims: %{
          "extensions" => %{
            "critical" => %{},
            "optional" => %{
              "com.example/identity-vlei" => %{"opaque" => "uninterpreted"}
            }
          }
        }
      )

    assert {:ok, decoded} =
             CharterAgreementProtocol.decode_party_descriptor(
               descriptor.compact,
               Limits.default()
             )

    assert decoded.extensions !=
             {:object, [{"critical", {:object, []}}, {"optional", {:object, []}}]}

    assert {:ok, facts} =
             CharterAgreementProtocol.verify_descriptor(
               descriptor.compact,
               nil,
               Limits.default()
             )

    assert facts.optional_extensions_retained == ["com.example/identity-vlei"]
  end

  test "receipt facts retain namespaces only while decoded receipts retain exact bodies" do
    setup = ChainFixture.base()
    limits = Limits.default()

    {:ok, chain} =
      CharterAgreementProtocol.verify_chain(
        [setup.genesis.bytes],
        setup.genesis |> ChainFixture.dual_acceptances(setup) |> Enum.map(& &1.compact),
        ChainFixture.descriptors(setup),
        [],
        limits
      )

    unknown = "org.invalid/receipt-evidence"

    claims =
      ReceiptFixture.claims(setup.genesis, %{
        "extensions" => %{
          "critical" => %{},
          "optional" => %{
            @price_observation => price_observation(),
            unknown => %{"opaque" => [1, "two"]}
          }
        }
      })

    compact = ReceiptFixture.compact(claims, setup.issuer)

    assert {:ok, facts} = CharterAgreementProtocol.verify_receipt(compact, chain, limits)
    assert facts.optional_extensions_retained == [@price_observation, unknown]
    refute inspect(facts) =~ "computed_amount_minor"
    refute inspect(facts) =~ "opaque"

    assert {:ok, decoded} = Receipt.decode_for_signing(compact, limits)
    assert {:object, regions} = decoded.extensions
    assert {"optional", {:object, retained}} = List.keyfind(regions, "optional", 0)
    assert Enum.map(retained, &elem(&1, 0)) == [@price_observation, unknown]
  end

  defp price_terms do
    %{
      "currency" => "USD",
      "base_amount_minor" => 10_000,
      "index" => %{
        "series_document_digest" => CharterRevisionFixture.tagged(:legal_text, "series"),
        "series_id" => "EXAMPLE-CPI",
        "observation_lag_days" => 2
      },
      "formula" => "index_plus_spread",
      "spread_bps" => 125,
      "floor_amount_minor" => 9_000,
      "cap_amount_minor" => 12_000,
      "tolerance_bps" => 50
    }
  end

  defp price_observation do
    %{
      "observed_index_digest" => CharterRevisionFixture.tagged(:legal_text, "observation"),
      "observation_instant" => "2026-08-25T12:00:00Z",
      "computed_amount_minor" => 10_125
    }
  end
end
