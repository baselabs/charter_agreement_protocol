defmodule CharterAgreementProtocol.ReleaseCandidateGate do
  alias CharterAgreementProtocol.{Canonicalization, Digest, SpecificationIdentity}
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

      # The pin is the package CONTENT identity (sorted unpacked path+bytes),
      # not the tarball bytes: hex.build's gzip layer is reproducible within
      # one OS but not across OSes (the macOS and Linux runners build
      # different byte-identical-content tarballs), so a byte pin recorded on
      # one OS can never pass a gate on the other. Content identity is
      # byte-order- and platform-independent and still detects any content
      # change.
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

    pins = [
      {"lib/charter_agreement_protocol/conformance/cli.ex", index_identity},
      {"verifier/core.ts", index_identity},
      {"verifier/core.ts", index["registry_digest"]}
    ]

    Enum.each(pins, fn {path, pin} ->
      if not String.contains?(File.read!(Path.join(@root, path)), pin),
        do: raise("certified identity missing from #{path}")
    end)
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
