# Records priv/release-metadata.json from the live corpus index and the
# normative specification tree. Run from the repository root after any
# deliberate spec-byte or corpus change:
#     mix run --no-start scripts/record_release_metadata.exs
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
  "verifier_runtime" => "node>=24.8"
}

tag_value = fn
  value when is_boolean(value) -> {:boolean, value}
  value when is_binary(value) -> {:string, value}
  nil -> :null
end

# The release identity is pinned repository-side (.release-archive.sha256),
# never inside the packaged metadata: a tarball cannot carry its own digest
# without changing it. The pin is the package CONTENT identity — the SHA-256
# over the unpacked archive's sorted path+bytes, excluding hex_metadata.config
# (whose embedded file list follows filesystem enumeration order, which
# differs across filesystems; its inputs — mix.exs and the hashed file set —
# are fully covered). priv/release-metadata.json is part of the package, so
# it is written FIRST — the pin must cover the final metadata bytes, or the
# next gate run drifts against the stale content it certified. The
# release-candidate gate rebuilds the archive twice, requires byte
# reproducibility within the run, and requires this content identity to
# equal the pin on any platform.

{:ok, bytes} =
  Canonicalization.encode(
    {:object, Enum.map(metadata, fn {key, value} -> {key, tag_value.(value)} end)}
  )

File.write!("priv/release-metadata.json", bytes)

archive_path = Path.join(System.tmp_dir!(), "cap-metadata-archive.tar")

{output, status} =
  System.cmd("mix", ["hex.build", "--output", archive_path], stderr_to_stdout: true)

if status != 0, do: raise("archive build failed\n#{output}")

unpack = Path.join(System.tmp_dir!(), "cap-metadata-unpack-#{System.unique_integer([:positive])}")
File.mkdir_p!(unpack)

{output, status} =
  System.cmd("mix", ["hex.build", "--unpack", "--output", unpack], stderr_to_stdout: true)

if status != 0, do: raise("archive unpack failed\n#{output}")

content_pin =
  unpack
  |> Path.join("**/*")
  |> Path.wildcard(match_dot: true)
  |> Enum.reject(&File.dir?/1)
  |> Enum.map(&{Path.relative_to(&1, unpack), File.read!(&1)})
  |> Enum.reject(fn {path, _bytes} -> path == "hex_metadata.config" end)
  |> Enum.sort()
  |> Enum.map_join(fn {path, bytes} -> path <> <<0>> <> <<byte_size(bytes)::64>> <> bytes end)
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.url_encode64(padding: false)

File.rm_rf!(unpack)
File.rm!(archive_path)
File.write!(".release-archive.sha256", content_pin <> "\n")

IO.puts("recorded priv/release-metadata.json spec_digest=#{spec_digest}")
