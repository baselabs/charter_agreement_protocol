alias CharterAgreementProtocol.Conformance.{Cli, Report}

defmodule CharterAgreementProtocol.ConformanceRegenerationGate do
  @root Path.expand("..", __DIR__)

  def run do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "cap-conformance-regeneration-#{System.unique_integer([:positive, :monotonic])}"
      )

    source = Path.join(@root, "priv/conformance")
    target = Path.join(scratch, "conformance")

    try do
      File.mkdir_p!(scratch)
      {:ok, _paths} = File.cp_r(source, target)

      {output, status} =
        System.cmd("mix", ["run", "scripts/generate_conformance_corpus.exs"],
          cd: @root,
          stderr_to_stdout: true,
          env: [{"CAP_CONFORMANCE_ROOT", target}]
        )

      if status != 0, do: raise("corpus regeneration failed\n#{output}")

      expected = files(source)
      actual = files(target)

      if actual != expected, do: raise("corpus regeneration changed certified bytes")

      IO.puts("conformance regeneration: byte-identical")
    after
      File.rm_rf!(scratch)
    end
  end

  defp files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reduce(%{}, fn path, files ->
      case File.lstat!(path) do
        %File.Stat{type: :directory} ->
          files

        %File.Stat{type: :regular} ->
          Map.put(files, Path.relative_to(path, root), File.read!(path))

        %File.Stat{type: type} ->
          raise "non-regular conformance entry: #{path} (#{type})"
      end
    end)
  end
end

case Cli.run(["--corpus", "priv/conformance"]) do
  0 ->
    CharterAgreementProtocol.ConformanceRegenerationGate.run()

    IO.puts(
      "conformance verification: certified index #{Report.index_identity(File.read!("priv/conformance/index.json"))}"
    )

  status ->
    Mix.raise("conformance verification exited #{status}")
end
