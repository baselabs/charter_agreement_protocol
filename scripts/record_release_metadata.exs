# Records priv/release-metadata.json from the live corpus index and the
# normative specification tree. Run from the repository root after any
# deliberate spec-byte or corpus change:
#     mix run scripts/record_release_metadata.exs
alias CharterAgreementProtocol.{
  Canonicalization,
  Conformance.Report,
  Digest,
  SpecificationIdentity
}

index_bytes = File.read!("priv/conformance/index.json")
index = :json.decode(index_bytes)

spec_files =
  "spec/**/*"
  |> Path.wildcard(match_dot: true)
  |> Enum.reject(&File.dir?/1)
  |> Enum.map(&{Path.relative_to(&1, "spec"), File.read!(&1)})

if spec_files == [], do: raise("empty specification set: nothing to record")

spec_digest =
  spec_files
  |> SpecificationIdentity.digest()
  |> Digest.to_tagged()

metadata = %{
  "archive_is_publication_authorization" => false,
  "corpus_digest" => index["corpus_digest"],
  "format" => "charter-agreement-protocol-release-metadata",
  "index_sha256_base64url" => Report.index_identity(index_bytes),
  "package" => "charter_agreement_protocol",
  "package_version" => Mix.Project.config()[:version],
  "registry_digest" => index["registry_digest"],
  "spec_digest" => spec_digest,
  "verifier_runtime" => "node>=24"
}

tag_value = fn
  value when is_boolean(value) -> {:boolean, value}
  value when is_binary(value) -> {:string, value}
  nil -> :null
end

{:ok, bytes} =
  Canonicalization.encode(
    {:object, Enum.map(metadata, fn {key, value} -> {key, tag_value.(value)} end)}
  )

File.write!("priv/release-metadata.json", bytes)
IO.puts("recorded priv/release-metadata.json spec_digest=#{spec_digest}")
