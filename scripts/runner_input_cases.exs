defmodule CharterAgreementProtocol.RunnerInputCases do
  alias CharterAgreementProtocol.Conformance.Corpus

  @deferred_surfaces ~w(descriptor_publication.verify receipt.inspect)

  def cases(cases) do
    surfaces = Corpus.surfaces() -- @deferred_surfaces

    profile_cases(cases, surfaces) ++
      context_cases(cases) ++
      order_cases(cases) ++
      float_cases(cases) ++ kind_cases(cases, surfaces) ++ chain_view_cases(cases)
  end

  # Exercise the shared runner inputs without adding rows to the certified census.
  def publication_cases(cases) do
    surfaces = ["descriptor_publication.verify"]
    profile_cases(cases, surfaces) ++ kind_cases(cases, surfaces)
  end

  def inspection_cases(cases) do
    surface = "receipt.inspect"
    base = valid_case(cases, surface)
    prefix = "receipt-inspect"

    largest =
      base["input"]["chain"]
      |> Map.values()
      |> List.flatten()
      |> then(&[base["input"]["compact"] | &1])
      |> Enum.map(&byte_size/1)
      |> Enum.max()

    profile_cases(cases, [surface]) ++
      receipt_context_cases(base, prefix, largest) ++
      receipt_order_cases(base, prefix) ++
      compact_float_cases(base, "receipt", prefix) ++
      range_float_cases(base, prefix, 8) ++
      kind_cases(cases, [surface]) ++ chain_view_cases(base, prefix, ["chain"])
  end

  defp profile_cases(cases, surfaces) do
    for surface <- surfaces,
        max_revision = if(surface in @deferred_surfaces, do: 8, else: 3),
        {suffix, profile, code} <- [
          {"null-profile", nil, "invalid_profile"},
          {"null-algorithms", %{"algorithms" => nil}, "invalid_profile"},
          {"null-revisions", %{"revisions" => nil}, "invalid_profile"},
          {"empty-profile", %{}, nil},
          {"missing-algorithms", %{"revisions" => %{"min" => 1, "max" => max_revision}}, nil},
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

    zero_limit =
      invalid(
        governing,
        "governing-zero-byte-limit",
        Map.put(governing["input"], "limits", %{"max_bytes" => 0}),
        "limit_exceeded"
      )

    revision_cases = [
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

    receipt_cases = receipt_context_cases(receipt, "receipt", byte_size(compact))
    [zero_limit] ++ receipt_cases ++ revision_cases
  end

  defp receipt_context_cases(base, prefix, bound) do
    input = base["input"]
    compact = input["compact"]

    [
      %{
        base
        | "id" => prefix <> "-artifact-byte-exact",
          "class" => "valid",
          "input" => Map.put(input, "limits", %{"max_bytes" => bound})
      },
      base
      |> invalid(
        prefix <> "-artifact-byte-over-limit",
        Map.put(input, "limits", %{"max_bytes" => bound - 1}),
        "limit_exceeded"
      )
      |> Map.put("class", "maximum_plus_one"),
      invalid(base, prefix <> "-missing-context", %{"compact" => compact}, "invalid_type"),
      invalid(
        base,
        prefix <> "-null-chain",
        %{"compact" => compact, "chain" => nil},
        "invalid_type"
      )
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
    json_cases ++ chain_cases ++ receipt_order_cases(receipt, "receipt")
  end

  defp receipt_order_cases(base, prefix) do
    for {suffix, limits} <- [
          {"items", %{"max_artifact_set_items" => 1}},
          {"bytes", %{"max_artifact_set_bytes" => 10}},
          {"artifact-bytes", %{"max_bytes" => 10}}
        ] do
      input = base["input"] |> put_in(["chain", "revisions"], []) |> Map.put("limits", limits)

      invalid(base, prefix <> "-empty-revisions-top-limits-" <> suffix, input, "limit_exceeded")
    end
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
      Enum.flat_map(~w(party_descriptor acceptance termination receipt), fn kind ->
        compact_float_cases(valid_case(cases, kind <> ".verify"), kind, kind <> "-verify")
      end)

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

    profiled_surfaces = ~w(party_descriptor.verify chain.verify_profile signing.prepare)

    range_cases =
      Enum.flat_map(profiled_surfaces, fn surface ->
        prefix = String.replace(surface, ".", "-")
        range_float_cases(valid_case(cases, surface), prefix, 3)
      end)

    claims_cases ++ verify_cases ++ revision_cases ++ range_cases
  end

  defp compact_float_cases(base, kind, prefix) do
    [header, payload, signature] = String.split(base["input"]["compact"], ".")
    claims = payload |> Base.url_decode64!(padding: false) |> :json.decode()

    for field <- integer_fields(kind) do
      bytes = float_json(Map.put(claims, field, claims[field] / 1))
      compact = Enum.join([header, Base.url_encode64(bytes, padding: false), signature], ".")

      invalid(
        base,
        prefix <> "-float-" <> String.replace(field, "_", "-"),
        Map.put(base["input"], "compact", compact),
        "invalid_type"
      )
    end
  end

  defp range_float_cases(base, prefix, maximum) do
    for {suffix, range} <- [
          {"minimum", %{"min" => 1.0, "max" => maximum}},
          {"maximum", %{"min" => 1, "max" => maximum / 1}}
        ] do
      invalid(
        base,
        prefix <> "-float-revision-" <> suffix,
        Map.put(base["input"], "profile", %{"revisions" => range}),
        "invalid_profile"
      )
    end
  end

  defp integer_fields("party_descriptor"), do: ~w(protocol_revision descriptor_number)
  defp integer_fields("termination"), do: ~w(protocol_revision)
  defp integer_fields(_kind), do: ~w(protocol_revision revision_number)

  defp float_json(claims) do
    {:ok, tagged} = CharterAgreementProtocol.Canonicalization.from_plain(claims)
    {:ok, bytes} = CharterAgreementProtocol.Internal.CaseJson.encode(tagged)
    bytes
  end

  defp kind_cases(cases, surfaces) do
    for surface <- surfaces,
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
    signing = Enum.find(cases, &(&1["id"] == "signing-ed25519-receipt"))

    chain_view_cases(valid_case(cases, "receipt.verify"), "receipt", ["chain"]) ++
      chain_view_cases(signing, "signing-receipt", ["context", "chain"])
  end

  defp chain_view_cases(base, prefix, path) do
    for {suffix, member, value} <- [
          {"limits", "limits", %{"max_artifact_set_items" => 1}},
          {"null-limits", "limits", nil},
          {"extra", "extra", true},
          {"profile", "profile", %{}}
        ] do
      input = update_in(base["input"], path, &Map.put(&1, member, value))
      invalid(base, prefix <> "-chain-view-" <> suffix, input, "invalid_type")
    end
  end

  defp valid_case(cases, surface) do
    Enum.find(cases, &(&1["surface"] == surface and &1["expect"]["status"] == "valid")) ||
      raise "no valid runner input fixture for #{surface}"
  end

  defp invalid(base, id, input, code),
    do: %{
      base
      | "id" => id,
        "class" => "invalid_type",
        "input" => input,
        "expect" => %{"status" => "invalid", "error_code" => code}
    }
end
