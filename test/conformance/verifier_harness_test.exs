defmodule CharterAgreementProtocol.Conformance.VerifierHarnessTest do
  use ExUnit.Case, async: true

  Code.require_file("../../scripts/verifier_source.exs", __DIR__)

  alias CharterAgreementProtocol.VerifierSource

  # These tests run the pinned TypeScript verifier source. Build it from the
  # local cache when it is missing or from an earlier pin, and fetch only when
  # the cache does not hold the pinned commit.
  setup_all do
    try do
      VerifierSource.current!()
    rescue
      RuntimeError ->
        try do
          VerifierSource.run(["--cached"])
        rescue
          RuntimeError -> VerifierSource.run([])
        end
    end

    :ok
  end

  # The pinned TypeScript verifier source (scripts/verifier_source.exs).
  defp verifier(file), do: Path.join(VerifierSource.path(), file)

  test "the pinned Node harness checks CAP bytes and reports its older applicability table" do
    {version, 0} = System.cmd("node", ["--version"])

    major =
      version |> String.trim_leading("v") |> String.split(".") |> hd() |> String.to_integer()

    assert major >= 24

    corpus = Path.expand("priv/conformance")
    # This pin predates CAP's receipt maximum_plus_one cell. Its refusal
    # is checked against CAP's current bytes.
    assert {output, 1} =
             System.cmd("node", [verifier("check-corpus.mjs"), corpus], stderr_to_stdout: true)

    assert String.trim(output) == "not-applicable cell"

    temporary = Path.join(System.tmp_dir!(), "cap-corpus-#{System.unique_integer([:positive])}")
    File.mkdir_p!(temporary)
    on_exit(fn -> File.rm_rf!(temporary) end)

    for path <- Path.wildcard(Path.join(corpus, "**/*")), not File.dir?(path) do
      relative = Path.relative_to(path, corpus)
      target = Path.join(temporary, relative)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(path, target)
    end

    File.write!(
      Path.join(temporary, "index.json"),
      File.read!(Path.join(temporary, "index.json")) <> " "
    )

    assert {output, 1} =
             System.cmd("node", [verifier("check-corpus.mjs"), temporary], stderr_to_stdout: true)

    assert String.trim(output) == "non-canonical index"
  end

  test "the harness has no third-party imports and the npm manifest stays repo-side" do
    source = File.read!(verifier("check-corpus.mjs"))

    assert Regex.scan(~r/from "([^"]+)"/, source)
           |> Enum.all?(fn [_, import] -> String.starts_with?(import, "node:") end)

    # The npm package lives in its own repository; only its pin ships in the
    # Hex package, never its source.
    assert File.exists?(verifier("package.json"))
    files = Mix.Project.config()[:package][:files]
    assert "priv/verifier-source.json" in files
    refute Enum.any?(files, &String.starts_with?(&1, "_build"))
  end

  test "the Node verifiers reject a non-regular certified path before reading it" do
    temporary =
      Path.join(System.tmp_dir!(), "cap-node-fifo-#{System.unique_integer([:positive])}")

    {:ok, _copied} = File.cp_r("priv/conformance", temporary)

    # The defensive path under test is reject-before-read of a NON-REGULAR
    # certified entry. A FIFO is the strongest fixture — an attempted read
    # would block forever — but mkfifo is POSIX-only. A directory would not
    # do: the walk recurses into directories and the failure surfaces as an
    # EISDIR read instead. On Windows a symlink to a regular file is
    # non-regular to lstat and proves the verifier inspects the certified
    # path itself rather than following it; if the runner refuses link
    # creation, the test says so and passes without claiming the substrate
    # proved anything — the POSIX lanes carry the red-capable form.
    if match?({:win32, _}, :os.type()) do
      File.rename!(Path.join(temporary, "index.json"), Path.join(temporary, "index.regular"))

      case :file.make_symlink(
             Path.join(temporary, "index.regular"),
             Path.join(temporary, "index.json")
           ) do
        :ok ->
          :ok

        {:error, reason} ->
          IO.puts("skipping the non-regular fixture: this host refuses link creation (#{reason})")
      end
    else
      File.rm!(Path.join(temporary, "index.json"))
      {_output, 0} = System.cmd("mkfifo", [Path.join(temporary, "index.json")])
    end

    try do
      for arguments <- [
            [verifier("cli.ts"), "--corpus", temporary],
            [verifier("check-corpus.mjs"), temporary]
          ] do
        task =
          Task.async(fn ->
            System.cmd("node", arguments, stderr_to_stdout: true)
          end)

        # The budget proves the verifier rejects the FIFO before reading it —
        # an attempted read blocks forever and outlives any budget — while
        # tolerating Node cold-start under CI load; 1s flaked on a busy
        # runner (startup alone crossed it).
        result = Task.yield(task, 10_000)
        if result == nil, do: Task.shutdown(task, :brutal_kill)

        assert {:ok, {output, status}} = result
        assert status == 1
        assert output =~ "non-regular corpus entry"
      end
    after
      File.rm_rf!(temporary)
    end
  end
end
