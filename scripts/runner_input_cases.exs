defmodule CharterAgreementProtocol.RunnerInputCases do
  alias CharterAgreementProtocol.Conformance.Corpus

  def cases(cases) do
    profile_cases(cases) ++
      context_cases(cases) ++
      order_cases(cases) ++ float_cases(cases) ++ kind_cases(cases) ++ chain_view_cases(cases)
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
      %{
        receipt
        | "id" => "receipt-artifact-byte-exact",
          "class" => "valid",
          "input" => Map.put(receipt["input"], "limits", %{"max_bytes" => byte_size(compact)})
      },
      invalid(
        receipt,
        "receipt-artifact-byte-over-limit",
        Map.put(receipt["input"], "limits", %{"max_bytes" => byte_size(compact) - 1}),
        "limit_exceeded"
      )
      |> Map.put("class", "maximum_plus_one"),
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

    receipt = valid_case(cases, "receipt.verify")

    receipt_cases =
      for {suffix, limits} <- [
            {"items", %{"max_artifact_set_items" => 1}},
            {"bytes", %{"max_artifact_set_bytes" => 10}},
            {"artifact-bytes", %{"max_bytes" => 10}}
          ] do
        input =
          receipt["input"] |> put_in(["chain", "revisions"], []) |> Map.put("limits", limits)

        invalid(receipt, "receipt-empty-revisions-top-limits-" <> suffix, input, "limit_exceeded")
      end

    json_cases ++ chain_cases ++ receipt_cases
  end

  defp float_cases(cases) do
    claims_cases =
      for kind <- ~w(party_descriptor acceptance termination receipt),
          field <- integer_fields(kind),
          label <- ~w(ed25519 mldsa65) do
        base = Enum.find(cases, &(&1["id"] == "signing-" <> label <> "-" <> kind))
        value = base["input"]["claims"][field] / 1

        invalid(
          base,
          "signing-" <> label <> "-" <> kind <> "-float-" <> String.replace(field, "_", "-"),
          put_in(base["input"], ["claims", field], value),
          "signing_input_invalid"
        )
      end

    verify_cases =
      for {kind, surface} <- [
            {"party_descriptor", "party_descriptor.verify"},
            {"acceptance", "acceptance.verify"},
            {"termination", "termination.verify"},
            {"receipt", "receipt.verify"}
          ],
          field <- integer_fields(kind) do
        base = valid_case(cases, surface)
        [header, payload, signature] = String.split(base["input"]["compact"], ".")
        claims = payload |> Base.url_decode64!(padding: false) |> :json.decode()
        bytes = float_json(Map.put(claims, field, claims[field] / 1))
        compact = Enum.join([header, Base.url_encode64(bytes, padding: false), signature], ".")

        invalid(
          base,
          kind <> "-verify-float-" <> String.replace(field, "_", "-"),
          Map.put(base["input"], "compact", compact),
          "invalid_type"
        )
      end

    revision = valid_case(cases, "charter_revision.decode")
    claims = :json.decode(revision["input"]["text"])

    revision_cases =
      for field <- ~w(protocol_revision revision_number release_number) do
        changed =
          if field == "release_number" do
            Map.update!(claims, "abp_bindings", fn bindings ->
              Enum.map(bindings, &Map.update!(&1, field, fn number -> number / 1 end))
            end)
          else
            Map.update!(claims, field, &(&1 / 1))
          end

        invalid(
          revision,
          "revision-float-" <> String.replace(field, "_", "-"),
          %{"text" => float_json(changed)},
          "invalid_type"
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

    claims_cases ++ verify_cases ++ revision_cases ++ range_cases
  end

  defp integer_fields("party_descriptor"), do: ~w(protocol_revision descriptor_number)
  defp integer_fields("termination"), do: ~w(protocol_revision)
  defp integer_fields(_kind), do: ~w(protocol_revision revision_number)

  defp float_json(claims) do
    {:ok, tagged} = CharterAgreementProtocol.Canonicalization.from_plain(claims)
    {:ok, bytes} = CharterAgreementProtocol.Internal.CaseJson.encode(tagged)
    bytes
  end

  defp kind_cases(cases) do
    for surface <- Corpus.surfaces(),
        {kind, value} <- [
          {"integer", "[1]"},
          {"integer", "{}"},
          {"integer", 1.0},
          {"float", 1},
          {"string", nil},
          {"boolean", "true"},
          {"array", %{}},
          {"object", []},
          {"null", false}
        ] do
      base = valid_case(cases, surface)

      suffix =
        if kind == "integer",
          do: to_string(Enum.find_index(["[1]", "{}", 1.0], &(&1 === value))),
          else: kind

      input =
        base["input"] |> Map.put("kind", kind) |> Map.put("value", value) |> kind_input(surface)

      invalid(
        base,
        String.replace(surface, ".", "-") <> "-kind-mismatch-" <> suffix,
        input,
        "invalid_type"
      )
    end
  end

  defp kind_input(input, surface) when surface in ["json.decode", "digest.hash"],
    do: Map.take(input, ["kind", "value", "domain", "tagged"])

  defp kind_input(input, _surface), do: input

  defp chain_view_cases(cases) do
    for {surface, base, path} <- [
          {"receipt", valid_case(cases, "receipt.verify"), ["chain"]},
          {"signing-receipt", Enum.find(cases, &(&1["id"] == "signing-ed25519-receipt")),
           ["context", "chain"]}
        ],
        {suffix, member, value} <- [
          {"limits", "limits", %{"max_artifact_set_items" => 1}},
          {"null-limits", "limits", nil},
          {"extra", "extra", true},
          {"profile", "profile", %{}}
        ] do
      input = update_in(base["input"], path, &Map.put(&1, member, value))
      invalid(base, surface <> "-chain-view-" <> suffix, input, "invalid_type")
    end
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
