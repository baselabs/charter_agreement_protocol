alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}
alias CharterAgreementProtocol.Conformance.Corpus

root = "priv/conformance"
case_format = "charter-agreement-protocol-conformance-cases"
index_format = "charter-agreement-protocol-conformance-corpus-index"

valid = fn output -> %{"status" => "valid", "output" => output} end
invalid = fn code -> %{"status" => "invalid", "error_code" => code} end

cases = [
  %{
    "id" => "base64url-empty",
    "surface" => "base64url.decode",
    "class" => "valid",
    "input" => %{"text" => ""},
    "expect" => valid.(%{"bytes_base64url" => ""})
  },
  %{
    "id" => "base64url-exact-two-chars",
    "surface" => "base64url.decode",
    "class" => "exact_bound",
    "input" => %{"text" => "AQ"},
    "expect" => valid.(%{"bytes_base64url" => "AQ"})
  },
  %{
    "id" => "base64url-padding-rejected",
    "surface" => "base64url.decode",
    "class" => "invalid_encoding",
    "input" => %{"text" => "AQ=="},
    "expect" => invalid.("base64url_padded")
  },
  %{
    "id" => "json-empty-object",
    "surface" => "json.decode",
    "class" => "valid",
    "input" => %{"text" => "{}"},
    "expect" => valid.(%{"tag" => "object", "members" => []})
  },
  %{
    "id" => "json-array-boundary-near",
    "surface" => "json.decode",
    "class" => "boundary_near",
    "input" => %{"text" => "[1]", "limits" => %{"max_array_items" => 2}},
    "expect" => valid.(%{"tag" => "array", "items" => [%{"tag" => "integer", "value" => 1}]})
  },
  %{
    "id" => "json-byte-exact-bound",
    "surface" => "json.decode",
    "class" => "exact_bound",
    "input" => %{"text" => "null", "limits" => %{"max_bytes" => 4}},
    "expect" => valid.(%{"tag" => "null"})
  },
  %{
    "id" => "json-byte-maximum-plus-one",
    "surface" => "json.decode",
    "class" => "maximum_plus_one",
    "input" => %{"text" => "null", "limits" => %{"max_bytes" => 3}},
    "expect" => invalid.("limit_exceeded")
  },
  %{
    "id" => "json-invalid-utf8",
    "surface" => "json.decode",
    "class" => "invalid_encoding",
    "input" => %{"bytes_base64url" => "_w"},
    "expect" => invalid.("invalid_encoding")
  },
  %{
    "id" => "json-non-binary",
    "surface" => "json.decode",
    "class" => "invalid_type",
    "input" => %{"kind" => "integer", "value" => 1},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "canonical-object",
    "surface" => "canonicalization.encode",
    "class" => "valid",
    "input" => %{"tag" => "object", "members" => [["a", %{"tag" => "integer", "value" => 1}]]},
    "expect" => valid.(%{"text" => "{\"a\":1}"})
  },
  %{
    "id" => "canonical-noncharacter",
    "surface" => "canonicalization.encode",
    "class" => "invalid_encoding",
    "input" => %{"tag" => "string_codepoint", "value" => "FFFF"},
    "expect" => invalid.("invalid_encoding")
  },
  %{
    "id" => "canonical-noncanonical-member-order",
    "surface" => "canonicalization.encode",
    "class" => "non_canonical_bytes",
    "input" => %{"text" => "{\"b\":1,\"a\":2}"},
    "expect" => invalid.("non_canonical_bytes")
  },
  %{
    "id" => "canonical-improper-term",
    "surface" => "canonicalization.encode",
    "class" => "invalid_type",
    "input" => %{"kind" => "improper_object"},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "digest-domain-separated",
    "surface" => "digest.hash",
    "class" => "valid",
    "input" => %{"domain" => "charter_revision_content", "bytes_base64url" => "e30"},
    "expect" => valid.(%{"algorithm" => "sha-256"})
  },
  %{
    "id" => "digest-non-bytes",
    "surface" => "digest.hash",
    "class" => "invalid_type",
    "input" => %{"kind" => "integer", "value" => 1},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "digest-content-mismatch",
    "surface" => "digest.hash",
    "class" => "digest_mismatch",
    "input" => %{
      "domain" => "charter_revision_content",
      "bytes_base64url" => "e30",
      "tagged" => "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    },
    "expect" => invalid.("digest_mismatch")
  },
  %{
    "id" => "schema-valid-object",
    "surface" => "schema.validate",
    "class" => "valid",
    "input" => %{"members" => %{"name" => "ok"}},
    "expect" => valid.(%{"members" => %{"name" => "ok"}})
  },
  %{
    "id" => "schema-wrong-type",
    "surface" => "schema.validate",
    "class" => "invalid_type",
    "input" => %{"members" => %{"name" => 1}},
    "expect" => invalid.("invalid_type")
  },
  %{
    "id" => "schema-constraint",
    "surface" => "schema.validate",
    "class" => "invalid_constraint",
    "input" => %{"members" => %{"name" => "!"}},
    "expect" => invalid.("constraint_violation")
  },
  %{
    "id" => "schema-cardinality",
    "surface" => "schema.validate",
    "class" => "invalid_cardinality",
    "input" => %{"members" => %{"name" => "a"}},
    "expect" => invalid.("cardinality_violation")
  },
  %{
    "id" => "schema-unknown-member",
    "surface" => "schema.validate",
    "class" => "unknown_member",
    "input" => %{"members" => %{"name" => "ok", "rogue" => true}},
    "expect" => invalid.("unknown_member")
  },
  %{
    "id" => "schema-missing-required",
    "surface" => "schema.validate",
    "class" => "missing_required",
    "input" => %{"members" => %{}},
    "expect" => invalid.("missing_required")
  },
  %{
    "id" => "schema-maximum-plus-one",
    "surface" => "schema.validate",
    "class" => "maximum_plus_one",
    "input" => %{"members" => %{"name" => "abcde"}},
    "expect" => invalid.("cardinality_violation")
  }
]

tagged = fn plain ->
  recur = fn
    _recur, nil ->
      :null

    _recur, value when is_boolean(value) ->
      {:boolean, value}

    _recur, value when is_integer(value) ->
      {:integer, value}

    _recur, value when is_float(value) ->
      {:float, value}

    _recur, value when is_binary(value) ->
      {:string, value}

    recur, value when is_list(value) ->
      {:array, Enum.map(value, &recur.(recur, &1))}

    recur, value when is_map(value) ->
      {:object, Enum.map(value, fn {key, item} -> {key, recur.(recur, item)} end)}
  end

  recur.(recur, plain)
end

canonical = fn value ->
  {:ok, bytes} = Canonicalization.encode(tagged.(value))
  bytes
end

raw_hash = fn bytes -> bytes |> Digest.of() |> Map.fetch!(:bytes) |> Base64Url.encode() end

grouped = Enum.group_by(cases, & &1["surface"])

files =
  Enum.map(Corpus.surfaces(), fn surface ->
    path = "cases/" <> String.replace(surface, ".", "-") <> ".json"
    surface_cases = Map.fetch!(grouped, surface)
    bytes = canonical.(%{"format" => case_format, "cases" => surface_cases})
    target = Path.join(root, path)
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, bytes)

    %{"path" => path, "sha256_base64url" => raw_hash.(bytes), "cases" => length(surface_cases)}
  end)

observed = Enum.frequencies_by(cases, &{&1["surface"], &1["class"]})

applicability =
  Map.new(Corpus.surfaces(), fn surface ->
    floor = Map.fetch!(Corpus.floor(), surface)

    cells =
      Map.new(Corpus.classes(), fn class ->
        if class in floor.required,
          do: {class, Map.get(observed, {surface, class}, 0)},
          else: {class, %{"n_a" => floor.n_a}}
      end)

    {surface, cells}
  end)

index = %{
  "format" => index_format,
  "corpus_digest" => "",
  "total_cases" => length(cases),
  "files" => files,
  "applicability" => applicability
}

index_without_digest = Map.delete(index, "corpus_digest")

identity =
  index_without_digest
  |> canonical.()
  |> then(&Digest.hash(:corpus_index, &1))
  |> Digest.to_tagged()

index = Map.put(index, "corpus_digest", identity)
File.mkdir_p!(root)
File.write!(Path.join(root, "index.json"), canonical.(index))
IO.puts(identity)
