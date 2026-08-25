alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest, ExtensionRegistry}
alias CharterAgreementProtocol.Conformance.Corpus

root = "priv/conformance"

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

loaded =
  Enum.map(Corpus.surfaces(), fn surface ->
    path = "cases/" <> String.replace(surface, ".", "-") <> ".json"
    bytes = File.read!(Path.join(root, path))

    %{"format" => "charter-agreement-protocol-conformance-cases", "cases" => cases} =
      :json.decode(bytes)

    {surface, path, bytes, cases}
  end)

cases = Enum.flat_map(loaded, &elem(&1, 3))
observed = Enum.frequencies_by(cases, &{&1["surface"], &1["class"]})

files =
  Enum.map(loaded, fn {_surface, path, bytes, surface_cases} ->
    %{"path" => path, "sha256_base64url" => raw_hash.(bytes), "cases" => length(surface_cases)}
  end)

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
  "format" => "charter-agreement-protocol-conformance-corpus-index",
  "corpus_digest" => "",
  "registry_digest" => ExtensionRegistry.digest() |> Digest.to_tagged(),
  "total_cases" => length(cases),
  "files" => files,
  "applicability" => applicability
}

identity =
  index
  |> Map.delete("corpus_digest")
  |> canonical.()
  |> then(&Digest.hash(:corpus_index, &1))
  |> Digest.to_tagged()

bytes = index |> Map.put("corpus_digest", identity) |> canonical.()
File.write!(Path.join(root, "index.json"), bytes)
IO.puts(identity)
IO.puts(raw_hash.(bytes))
