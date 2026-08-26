defmodule CharterAgreementProtocol.VerifierAgreementGate do
  @root Path.expand("..", __DIR__)
  @corpus "priv/conformance"
  @verifier "verifier"
  @escript "charter_agreement_protocol"

  @seeded_reds [
    %{
      name: "verdict-comparison-inverted",
      path: "core.ts",
      from: "agree: canonical(actual) === canonical(one.expect)",
      to: "agree: canonical(actual) !== canonical(one.expect)",
      exit: 1
    },
    %{
      name: "report-format-drift",
      path: "core.ts",
      from: "const REPORT_FORMAT = \"charter-agreement-protocol-conformance-report\";",
      to: "const REPORT_FORMAT = \"charter-agreement-protocol-conformance-report-drift\";",
      exit: 0
    },
    %{
      name: "certified-index-drift",
      path: "core.ts",
      from:
        "export const CERTIFIED_INDEX_SHA256_BASE64URL = \"SiGK6zgrI9Rv5BvBPgj3-EexxJ1udz8-XtDDjeOiRv0\";",
      to:
        "export const CERTIFIED_INDEX_SHA256_BASE64URL = \"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\";",
      exit: 1
    }
  ]

  def run do
    node = find_node!()
    build_escript!()

    try do
      elixir = run_elixir!(@corpus)
      typescript = run_typescript!(node, @corpus)
      equal!(elixir, typescript, "repository corpus")

      {archive_root, archive_corpus} = build_archive!()

      try do
        equal!(elixir, run_elixir!(archive_corpus), "archive corpus Elixir")
        equal!(elixir, run_typescript!(node, archive_corpus), "archive corpus TypeScript")
      after
        File.rm_rf!(archive_root)
      end

      {self_output, 0} =
        System.cmd(node, [Path.join(@verifier, "self-checks.ts")],
          cd: @root,
          stderr_to_stdout: true
        )

      IO.write(self_output)
      Enum.each(@seeded_reds, &seeded_red!(&1, node, typescript))
      IO.puts("verifier agreement: byte-identical repository and archive reports")
    after
      File.rm(Path.join(@root, @escript))
    end
  end

  defp build_escript! do
    {build_output, build_status} =
      System.cmd("mix", ["escript.build"], cd: @root, stderr_to_stdout: true)

    if build_status != 0, do: raise("escript build failed\n#{build_output}")
  end

  defp run_elixir!(corpus) do
    {output, status} =
      System.cmd(Path.join(@root, @escript), ["--corpus", corpus],
        cd: @root,
        stderr_to_stdout: true
      )

    if status != 0, do: raise("Elixir verifier failed\n#{output}")
    output
  end

  defp run_typescript!(node, corpus) do
    {output, status} =
      System.cmd(node, [Path.join(@verifier, "cli.ts"), "--corpus", corpus],
        cd: @root,
        stderr_to_stdout: true
      )

    if status != 0, do: raise("TypeScript verifier failed\n#{output}")
    output
  end

  defp equal!(left, right, label) do
    if left != right, do: raise("report bytes differ: #{label}")
    IO.puts("agreement: #{label}")
  end

  defp build_archive! do
    directory = temporary("archive")
    unpack = Path.join(directory, "package")

    {output, status} =
      System.cmd("mix", ["hex.build", "--unpack", "--output", unpack],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"MIX_QUIET", "1"}]
      )

    if status != 0, do: raise("archive unpack failed\n#{output}")
    {directory, Path.join(unpack, @corpus)}
  end

  defp seeded_red!(seed, node, baseline) do
    directory = temporary(seed.name)

    try do
      verifier = Path.join(directory, "verifier")
      corpus = Path.join(directory, "corpus")
      File.cp_r!(Path.join(@root, @verifier), verifier)
      File.cp_r!(Path.join(@root, @corpus), corpus)
      mutate_once!(Path.join(verifier, seed.path), seed.from, seed.to)

      {output, status} =
        System.cmd(node, [Path.join(verifier, "cli.ts"), "--corpus", corpus],
          stderr_to_stdout: true
        )

      if status != seed.exit, do: raise("seeded red wrong exit: #{seed.name}\n#{output}")
      if output == baseline, do: raise("seeded red did not diverge: #{seed.name}")
      IO.puts("seeded red fired: #{seed.name}")
    after
      File.rm_rf!(directory)
    end
  end

  defp mutate_once!(path, from, to) do
    bytes = File.read!(path)
    if length(:binary.matches(bytes, from)) != 1, do: raise("non-unique seed anchor: #{path}")
    File.write!(path, String.replace(bytes, from, to))
  end

  defp temporary(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "cap-verifier-#{label}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp find_node! do
    path = System.find_executable("node") || raise("Node >= 24 is required")
    {"v" <> version, 0} = System.cmd(path, ["--version"])
    major = version |> String.split(".") |> hd() |> String.to_integer()
    if major < 24, do: raise("Node >= 24 is required; found #{major}")
    path
  end
end

CharterAgreementProtocol.VerifierAgreementGate.run()
