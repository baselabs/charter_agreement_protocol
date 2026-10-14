defmodule CharterAgreementProtocol.RunnerInputCases do
  alias CharterAgreementProtocol.Conformance.Corpus

  def cases(cases) do
    profile_cases(cases) ++ context_cases(cases) ++ order_cases(cases) ++ float_cases(cases)
  end

  defp profile_cases(cases) do
    for surface <- Corpus.surfaces(),
        {suffix, profile, code} <- [
          {"null-profile", nil, "invalid_profile"},
          {"null-algorithms", %{"algorithms" => nil}, "invalid_profile"},
          {"null-revisions", %{"revisions" => nil}, "invalid_profile"},
          {"empty-profile", %{}, nil},
          {"missing-algorithms", %{"revisions" => %{"min" => 1, "max" => 3}}, nil},
          {"missing-revisions",
           %{"algorithms" => ["EdDSA", "Ed25519", "ML-DSA-44", "ML-DSA-65", "ML-DSA-87"]}, nil}
        ] do
      base = valid_case(cases, surface)
      id = String.replace(surface, ".", "-") <> "-" <> suffix
      input = Map.put(base["input"], "profile", profile)
      if code, do: invalid(base, id, input, code), else: %{base | "id" => id, "input" => input}
    end
  end

  defp context_cases(cases) do
    governing = valid_case(cases, "governing_revision")
    receipt = valid_case(cases, "receipt.verify")
    compact = receipt["input"]["compact"]
    revision = valid_case(cases, "charter_revision.decode")
    claims = :json.decode(revision["input"]["text"]) |> Map.put("abp_bindings", [])
    {:ok, text} = CharterAgreementProtocol.Canonicalization.encode_plain(claims)

    [
      invalid(
        governing,
        "governing-zero-byte-limit",
        Map.put(governing["input"], "limits", %{"max_bytes" => 0}),
        "limit_exceeded"
      ),
      invalid(receipt, "receipt-missing-context", %{"compact" => compact}, "invalid_type"),
      invalid(
        receipt,
        "receipt-null-chain",
        %{"compact" => compact, "chain" => nil},
        "invalid_type"
      ),
      invalid(
        receipt,
        "receipt-malformed-revision-context",
        %{"compact" => compact, "revision_text" => "{"},
        "invalid_syntax"
      ),
      %{
        revision
        | "id" => "revision-no-bindings",
          "input" => %{"text" => text},
          "expect" => %{
            "status" => "valid",
            "output" =>
              Map.merge(revision["expect"]["output"], %{
                "abp_binding" => nil,
                "revision_digest" =>
                  CharterAgreementProtocol.Digest.hash(:charter_revision_content, text)
                  |> CharterAgreementProtocol.Digest.to_tagged()
              })
          }
      }
    ]
  end

  defp order_cases(cases) do
    json = valid_case(cases, "json.decode")
    chain = valid_case(cases, "chain.verify")
    signing = Enum.find(cases, &(&1["id"] == "signing-ed25519-acceptance"))
    empty = Map.put(chain["input"], "revisions", [])

    json_cases =
      for {suffix, input, code} <- [
            {"incomplete-before-depth", %{"text" => "{", "limits" => %{"max_depth" => 0}},
             "invalid_syntax"},
            {"depth-before-later-syntax", %{"text" => "[bad", "limits" => %{"max_depth" => 0}},
             "limit_exceeded"},
            {"limits-before-input-type", %{"text" => 42, "limits" => %{"max_depth" => -1}},
             "invalid_limits"},
            {"input-type-with-valid-limits", %{"text" => 42, "limits" => %{"max_depth" => 0}},
             "invalid_type"}
          ],
          do: invalid(json, "json-" <> suffix, input, code)

    chain_cases =
      for {suffix, set, limits, code} <- [
            {"valid-descriptors", empty, %{}, "chain_invalid"},
            {"strict-limits", empty, %{"max_artifact_set_items" => 1}, "limit_exceeded"},
            {"malformed-descriptor", Map.put(empty, "descriptors", ["bad"]), %{},
             "compact_invalid"}
          ],
          surface <- ["chain.verify", "signing.prepare"] do
        {base, input} =
          if surface == "chain.verify" do
            {chain, Map.put(set, "limits", limits)}
          else
            {signing,
             signing["input"] |> Map.put("context", %{"set" => set}) |> Map.put("limits", limits)}
          end

        invalid(
          base,
          String.replace(surface, ".", "-") <> "-empty-revisions-" <> suffix,
          input,
          code
        )
      end

    json_cases ++ chain_cases
  end

  defp float_cases(cases) do
    claims_cases =
      for kind <- ~w(party_descriptor acceptance termination receipt) do
        base = Enum.find(cases, &(&1["id"] == "signing-ed25519-" <> kind))

        invalid(
          base,
          "signing-" <> kind <> "-float-protocol-revision",
          put_in(base["input"], ["claims", "protocol_revision"], 2.0),
          "signing_input_invalid"
        )
      end

    range_cases =
      for surface <- ~w(party_descriptor.verify chain.verify_profile signing.prepare),
          {suffix, range} <- [
            {"minimum", %{"min" => 1.0, "max" => 3}},
            {"maximum", %{"min" => 1, "max" => 3.0}}
          ] do
        base = valid_case(cases, surface)

        invalid(
          base,
          String.replace(surface, ".", "-") <> "-float-revision-" <> suffix,
          Map.put(base["input"], "profile", %{"revisions" => range}),
          "invalid_profile"
        )
      end

    claims_cases ++ range_cases
  end

  defp valid_case(cases, surface),
    do: Enum.find(cases, &(&1["surface"] == surface and &1["expect"]["status"] == "valid"))

  defp invalid(base, id, input, code),
    do: %{
      base
      | "id" => id,
        "class" => "invalid_type",
        "input" => input,
        "expect" => %{"status" => "invalid", "error_code" => code}
    }
end
