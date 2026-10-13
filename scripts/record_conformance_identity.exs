alias CharterAgreementProtocol.{Conformance.Report, Digest, SpecificationIdentity}

index_bytes = File.read!("priv/conformance/index.json")
index = :json.decode(index_bytes)
index_sha = Report.index_identity(index_bytes)

replace = fn path, pattern, value ->
  bytes = File.read!(path)
  if length(Regex.scan(pattern, bytes)) != 1, do: raise("identity anchor is not unique: #{path}")
  File.write!(path, Regex.replace(pattern, bytes, fn _match, prefix -> prefix <> value end))
end

replace.(
  "lib/charter_agreement_protocol/conformance/cli.ex",
  ~r/(@certified_index_sha256_base64url ")[^"]+/,
  index_sha
)

replace.("test/architecture/package_boundary_test.exs", ~r/(@index_sha ")[^"]+/, index_sha)
version = Regex.escape(Mix.Project.config()[:version])

pattern =
  Regex.compile!(
    "(package_versions: \\[\\\"#{version}\\\"\\],\\s+verification_semantics: \\d+,\\s+census_digest: \\\")[^\\\"]+"
  )

replace.("lib/charter_agreement_protocol/release_identity.ex", pattern, index["corpus_digest"])

spec_digest =
  "spec/**/*"
  |> Path.wildcard(match_dot: true)
  |> Enum.reject(&File.dir?/1)
  |> Enum.map(&{Path.relative_to(&1, "spec"), File.read!(&1)})
  |> SpecificationIdentity.digest()
  |> Digest.to_tagged()

guide = "docs/guides/conformance.md"
replace.(guide, ~r/(\| Corpus digest \| `)[^`]+/, index["corpus_digest"])
replace.(guide, ~r/(\| Index SHA-256 \(base64url\) \| `)[^`]+/, index_sha)
replace.(guide, ~r/(\| Extension registry digest \| `)[^`]+/, index["registry_digest"])
replace.(guide, ~r/(\| Specification digest \| `)[^`]+/, spec_digest)

replace.(
  guide,
  ~r/(\| Cases \| )[^|]+/,
  "#{index["total_cases"]}, in #{length(index["files"])} case files "
)

IO.puts("recorded corpus identities: #{index["total_cases"]} cases index_sha256=#{index_sha}")
