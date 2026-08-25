defmodule CharterAgreementProtocol.Conformance.VerifierHarnessTest do
  use ExUnit.Case, async: true

  test "the Node harness independently accepts shipped bytes and rejects index corruption" do
    {version, 0} = System.cmd("node", ["--version"])

    major =
      version |> String.trim_leading("v") |> String.split(".") |> hd() |> String.to_integer()

    assert major >= 24

    assert {output, 0} = System.cmd("node", ["verifier/check-corpus.mjs", "priv/conformance"])
    assert String.starts_with?(output, "sha-256:")

    temporary = Path.join(System.tmp_dir!(), "cap-corpus-#{System.unique_integer([:positive])}")
    File.mkdir_p!(temporary)
    on_exit(fn -> File.rm_rf!(temporary) end)

    for path <- Path.wildcard("priv/conformance/**/*"), not File.dir?(path) do
      relative = Path.relative_to(path, "priv/conformance")
      target = Path.join(temporary, relative)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(path, target)
    end

    File.write!(
      Path.join(temporary, "index.json"),
      File.read!(Path.join(temporary, "index.json")) <> " "
    )

    assert {_output, exit_status} =
             System.cmd("node", ["verifier/check-corpus.mjs", temporary], stderr_to_stdout: true)

    assert exit_status != 0
  end

  test "the harness has no package manager surface or third-party imports" do
    source = File.read!("verifier/check-corpus.mjs")
    refute File.exists?("verifier/package.json")

    assert Regex.scan(~r/from "([^"]+)"/, source)
           |> Enum.all?(fn [_, import] -> String.starts_with?(import, "node:") end)
  end

  test "the Node verifiers reject a non-regular certified path before reading it" do
    temporary =
      Path.join(System.tmp_dir!(), "cap-node-fifo-#{System.unique_integer([:positive])}")

    {:ok, _copied} = File.cp_r("priv/conformance", temporary)
    File.rm!(Path.join(temporary, "index.json"))
    {_output, 0} = System.cmd("mkfifo", [Path.join(temporary, "index.json")])

    try do
      for arguments <- [
            ["verifier/cli.ts", "--corpus", temporary],
            ["verifier/check-corpus.mjs", temporary]
          ] do
        task =
          Task.async(fn ->
            System.cmd("node", arguments, stderr_to_stdout: true)
          end)

        result = Task.yield(task, 1_000)
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
