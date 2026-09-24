defmodule CharterAgreementProtocol.ReleaseCandidateGate do
  alias CharterAgreementProtocol.{
    Algorithm,
    Canonicalization,
    Digest,
    ReleaseIdentity,
    SpecificationIdentity
  }

  alias CharterAgreementProtocol.Conformance.Report

  @root Path.expand("..", __DIR__)
  @metadata "priv/release-metadata.json"
  @index "priv/conformance/index.json"
  @spec_root "spec"
  @forbidden_prefixes [".env", ".kimosabe", "scripts/", "test/", "verifier/"]

  def run do
    verify_metadata!()
    verify_project!()
    verify_package_inputs!()

    directory = temporary()

    try do
      first = build_archive!(Path.join(directory, "first.tar"))
      second = build_archive!(Path.join(directory, "second.tar"))
      if first != second, do: raise("release archive reproducibility drift")

      unpack = Path.join(directory, "package")
      unpack!(unpack)
      verify_unpacked!(unpack)

      # The pin is the package CONTENT identity (sorted unpacked path+bytes,
      # excluding hex_metadata.config), not the tarball bytes: hex.build's
      # gzip layer is reproducible within one OS but not across OSes, and
      # hex_metadata.config itself embeds the file list in filesystem
      # enumeration order, which differs between filesystems. Every other
      # file is git-tracked content, and hex_metadata.config is a pure
      # function of mix.exs (packaged and hashed) plus that hashed file set,
      # so the identity still detects any content change on any platform.
      content_pin = content_identity!(unpack)

      case File.read(".release-archive.sha256") do
        {:ok, recorded} ->
          if String.trim(recorded) != content_pin,
            do:
              raise(
                "release content identity drift: pin #{String.trim(recorded)} content #{content_pin}"
              )

        :error ->
          raise("repository carries no .release-archive.sha256 pin")
      end

      IO.puts(
        "release candidate: content_sha256=#{content_pin} archive_sha256=#{first} publication_authorized=false"
      )
    after
      File.rm_rf!(directory)
    end
  end

  defp content_identity!(unpack) do
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
  end

  defp verify_metadata! do
    metadata_bytes = File.read!(Path.join(@root, @metadata))
    {:ok, _value} = Canonicalization.verify(metadata_bytes)
    metadata = :json.decode(metadata_bytes)
    index_bytes = File.read!(Path.join(@root, @index))
    index = :json.decode(index_bytes)
    index_identity = Report.index_identity(index_bytes)

    expected = %{
      "archive_is_publication_authorization" => false,
      "corpus_digest" => index["corpus_digest"],
      "format" => "charter-agreement-protocol-release-metadata",
      "index_sha256_base64url" => index_identity,
      "package" => "charter_agreement_protocol",
      "package_version" => Mix.Project.config()[:version],
      "registry_digest" => index["registry_digest"],
      "spec_digest" => live_spec_digest(),
      "verifier_runtime" => "node>=24.8"
    }

    if Map.take(metadata, Map.keys(expected)) != expected,
      do: raise("release metadata drift")

    verify_release_identity_members!(metadata)

    pins = [
      {"lib/charter_agreement_protocol/conformance/cli.ex", index_identity},
      {"verifier/core.ts", index_identity},
      {"verifier/core.ts", index["registry_digest"]},
      # The shipped docs' certified-identity tables must carry the live
      # values — a truncated or stale transcription (the 0.3.1 review caught
      # a 42-character index SHA) must fail this gate, not reach consumers.
      {"docs/guides/conformance.md", index_identity},
      {"docs/guides/conformance.md", index["corpus_digest"]},
      {"docs/guides/conformance.md", index["registry_digest"]},
      {"docs/guides/conformance.md", live_spec_digest()},
      {"docs/test-vectors.md", index_identity},
      {"docs/test-vectors.md", index["corpus_digest"]},
      {"docs/test-vectors.md", index["registry_digest"]},
      {"docs/test-vectors.md", live_spec_digest()}
    ]

    Enum.each(pins, fn {path, pin} ->
      if not String.contains?(File.read!(Path.join(@root, path)), pin),
        do: raise("certified identity missing from #{path}")
    end)
  end

  # The release-identity members are data-in-code projections: the archive
  # pin authenticates the manifest BYTES, this comparison authenticates their
  # TRUTH. A stale semantics version, drifted limits table, or hand-edited
  # compatibility matrix fails the gate even when the bytes are self-consistent.
  defp verify_release_identity_members!(metadata) do
    limits = fn value ->
      CharterAgreementProtocol.Limits.fields()
      |> Enum.map(&{Atom.to_string(&1), Map.get(value, &1)})
      |> Map.new()
    end

    expected_members = %{
      "manifest_version" => ReleaseIdentity.manifest_version(),
      "verification_semantics_version" => ReleaseIdentity.verification_semantics(),
      "limits" => %{
        "default" => limits.(CharterAgreementProtocol.Limits.default()),
        "maximum" => limits.(CharterAgreementProtocol.Limits.maximums())
      },
      "signature_registry_digest" =>
        Algorithm.registry_digest() |> CharterAgreementProtocol.Digest.to_tagged(),
      "signature_algorithms" =>
        Enum.map(Algorithm.registry(), fn row ->
          %{
            "name" => row.name,
            "min_protocol_revision" => row.min_protocol_revision,
            "key_algorithm" => row.key_algorithm,
            "public_key_bytes" => row.public_key_bytes,
            "signature_bytes" => row.signature_bytes
          }
        end),
      "compatibility" =>
        Enum.map(ReleaseIdentity.compatibility(), fn row ->
          %{
            "package_versions" => row.package_versions,
            "verification_semantics" => row.verification_semantics,
            "census_digest" => row.census_digest,
            "protocol_revisions" => row.protocol_revisions,
            "transitions" =>
              Enum.map(row.transitions, fn transition ->
                %{
                  "class" => Atom.to_string(transition.class),
                  "direction" => Atom.to_string(transition.direction),
                  "description" => transition.description
                }
              end)
          }
        end)
    }

    if Map.take(metadata, Map.keys(expected_members)) != expected_members,
      do: raise("release identity members drifted from live values")

    # The additive-only contract: the shipped manifest may carry exactly the
    # declared members — a removed or renamed member is a manifest-version
    # bump, not a silent edit.
    member_set =
      (Map.keys(expected_members) ++
         [
           "archive_is_publication_authorization",
           "corpus_digest",
           "format",
           "index_sha256_base64url",
           "package",
           "package_version",
           "registry_digest",
           "spec_digest",
           "verifier_runtime"
         ])
      |> Enum.sort()

    if Map.keys(metadata) != member_set,
      do: raise("release metadata member set changed")
  end

  defp live_spec_digest do
    files = spec_files()

    if files == [],
      do: raise("empty specification set: nothing to certify")

    files
    |> SpecificationIdentity.digest()
    |> Digest.to_tagged()
  end

  defp spec_files do
    @root
    |> Path.join(@spec_root <> "/**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
    |> Enum.map(&{Path.relative_to(&1, Path.join(@root, @spec_root)), File.read!(&1)})
  end

  defp verify_project! do
    project = Mix.Project.config()

    if String.contains?(File.read!(Path.join(@root, "mix.exs")), "hex.publish"),
      do: raise("publication toolpath present")

    Enum.each(project[:deps], fn dependency ->
      {name, options} = normalize_dependency(dependency)

      unless Keyword.get(options, :runtime) == false and
               Enum.sort(List.wrap(Keyword.get(options, :only))) == [:dev, :test] and
               not Keyword.has_key?(options, :path) and not Keyword.has_key?(options, :git) do
        raise("non-release dependency boundary: #{name}")
      end
    end)
  end

  defp normalize_dependency({name, requirement, options}) when is_binary(requirement),
    do: {name, options}

  defp normalize_dependency({name, options}) when is_list(options), do: {name, options}

  defp verify_package_inputs! do
    inputs = package_inputs()
    if inputs == [], do: raise("empty package boundary")

    Enum.each(inputs, fn path ->
      relative = Path.relative_to(path, @root)

      if Enum.any?(@forbidden_prefixes, &String.starts_with?(relative, &1)),
        do: raise("forbidden package input: #{relative}")

      case File.lstat!(path).type do
        :regular -> :ok
        other -> raise("non-regular package input #{relative}: #{other}")
      end
    end)
  end

  defp build_archive!(path) do
    {output, status} =
      System.cmd("mix", ["hex.build", "--output", path],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"MIX_QUIET", "1"}]
      )

    if status != 0, do: raise("archive build failed\n#{output}")
    path |> File.read!() |> Digest.of() |> Map.fetch!(:bytes) |> Base.encode16(case: :lower)
  end

  defp unpack!(path) do
    {output, status} =
      System.cmd("mix", ["hex.build", "--unpack", "--output", path],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"MIX_QUIET", "1"}]
      )

    if status != 0, do: raise("archive unpack failed\n#{output}")
  end

  defp verify_unpacked!(unpack) do
    observed =
      unpack
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, unpack))
      |> Enum.sort()

    expected = ["hex_metadata.config" | Enum.map(package_inputs(), &Path.relative_to(&1, @root))]
    expected = Enum.sort(expected)

    if observed != expected do
      missing = expected -- observed
      extra = observed -- expected
      raise("unpacked archive boundary drift missing=#{inspect(missing)} extra=#{inspect(extra)}")
    end

    metadata = File.read!(Path.join(unpack, @metadata))

    if metadata != File.read!(Path.join(@root, @metadata)),
      do: raise("archive metadata byte drift")
  end

  defp package_inputs do
    Mix.Project.config()[:package][:files]
    |> Enum.flat_map(fn relative ->
      path = Path.join(@root, relative)

      if File.dir?(path) do
        path |> Path.join("**/*") |> Path.wildcard() |> Enum.reject(&File.dir?/1)
      else
        [path]
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp temporary do
    path =
      Path.join(
        System.tmp_dir!(),
        "cap-release-candidate-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end

CharterAgreementProtocol.ReleaseCandidateGate.run()
