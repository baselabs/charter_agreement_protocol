# Records priv/release-metadata.json from the live corpus index and the
# normative specification tree. Run from the repository root after any
# deliberate spec-byte or corpus change:
#     mix run --no-start scripts/record_release_metadata.exs
alias CharterAgreementProtocol.{
  Algorithm,
  Canonicalization,
  Conformance.Report,
  Digest,
  ReleaseIdentity,
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

limits_object = fn limits ->
  CharterAgreementProtocol.Limits.fields()
  |> Enum.map(fn field -> {Atom.to_string(field), {:integer, Map.get(limits, field)}} end)
end

registry_rows =
  Enum.map(Algorithm.registry(), fn row ->
    {:object,
     [
       {"name", {:string, row.name}},
       {"min_protocol_revision", {:integer, row.min_protocol_revision}},
       {"key_algorithm", {:string, row.key_algorithm}},
       {"public_key_bytes", {:integer, row.public_key_bytes}},
       {"signature_bytes", {:integer, row.signature_bytes}}
     ]}
  end)

compatibility_rows =
  Enum.map(ReleaseIdentity.compatibility(), fn row ->
    {:object,
     [
      {"package_versions", {:array, Enum.map(row.package_versions, &{:string, &1})}},
      {"verification_semantics", {:integer, row.verification_semantics}},
      {"census_digest", {:string, row.census_digest}},
      {"protocol_revisions", {:array, Enum.map(row.protocol_revisions, &{:integer, &1})}},
       {"transitions",
        {:array,
         Enum.map(row.transitions, fn transition ->
           {:object,
            [
              {"class", {:string, Atom.to_string(transition.class)}},
              {"direction", {:string, Atom.to_string(transition.direction)}},
              {"description", {:string, transition.description}}
            ]}
         end)}}
     ]}
  end)

metadata = %{
  "archive_is_publication_authorization" => {:boolean, false},
  "compatibility" => {:array, compatibility_rows},
  "corpus_digest" => {:string, index["corpus_digest"]},
  "format" => {:string, "charter-agreement-protocol-release-metadata"},
  "index_sha256_base64url" => {:string, Report.index_identity(index_bytes)},
  "limits" =>
    {:object,
     [
       {"default", {:object, limits_object.(CharterAgreementProtocol.Limits.default())}},
       {"maximum", {:object, limits_object.(CharterAgreementProtocol.Limits.maximums())}}
     ]},
  "manifest_version" => {:integer, ReleaseIdentity.manifest_version()},
  "package" => {:string, "charter_agreement_protocol"},
  "package_version" => {:string, Mix.Project.config()[:version]},
  "registry_digest" => {:string, index["registry_digest"]},
  "signature_algorithms" => {:array, registry_rows},
  "signature_registry_digest" =>
    {:string, Algorithm.registry_digest() |> CharterAgreementProtocol.Digest.to_tagged()},
  "spec_digest" => {:string, spec_digest},
  "verification_semantics_version" => {:integer, ReleaseIdentity.verification_semantics()},
  "verifier_runtime" => {:string, "node>=24.8"}
}

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

{:ok, bytes} = Canonicalization.encode({:object, Enum.map(metadata, fn {key, value} -> {key, value} end)})

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
