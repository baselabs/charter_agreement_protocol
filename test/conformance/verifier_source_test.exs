defmodule CharterAgreementProtocol.Conformance.VerifierSourceTest do
  use ExUnit.Case, async: false

  setup do
    directory = Path.join(System.tmp_dir!(), "cap-pin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    source = Path.join(directory, "source")
    repo = Path.join(directory, "cap")
    init(source)

    pins =
      for number <- 1..3 do
        File.write!(Path.join(source, "data"), to_string(number))
        git!(source, ["add", "data"])
        git!(source, ["commit", "--quiet", "-m", "Update verifier data"])
        git!(source, ["rev-parse", "HEAD"]) |> String.trim()
      end

    init(repo)
    copy_script(repo)
    pin(repo, hd(pins))
    commit(repo)
    %{directory: directory, source: source, repo: repo, pins: pins}
  end

  test "the newest committed pin must move forward across a first-parent merge", context do
    [first, second, third] = context.pins
    git!(context.repo, ["checkout", "--quiet", "-b", "side"])
    pin(context.repo, third)
    commit(context.repo)
    git!(context.repo, ["checkout", "--quiet", "main"])
    pin(context.repo, second)
    commit(context.repo)

    git!(context.repo, [
      "merge",
      "--quiet",
      "--no-ff",
      "-s",
      "ours",
      "side",
      "-m",
      "Keep main pin"
    ])

    {output, 0} = run(context.repo, context.source)
    assert output =~ "materialized"

    pin(context.repo, first)
    commit(context.repo)
    {output, status} = run(context.repo, context.source)
    assert status != 0
    assert output =~ "newest pin change moves backward"

    pin(context.repo, third)
    commit(context.repo)
    {output, 0} = run(context.repo, context.source)
    assert output =~ "materialized"
    assert File.read!(Path.join(context.repo, "_build/verifier-source/data")) == "3"

    pin(context.repo, first)
    {output, status} = run(context.repo, context.source)
    assert status != 0
    assert output =~ "newest pin change moves backward"
  end

  test "a real shallow clone cannot supply pin history", context do
    clone = Path.join(context.directory, "shallow")

    git!(context.directory, ["clone", "--quiet", "--depth", "1", "file://" <> context.repo, clone])

    copy_script(clone)
    {output, status} = run(clone, context.source)
    assert status != 0
    assert output =~ "needs a full clone"
  end

  test "a directory without a checkout cannot supply pin history", context do
    directory = Path.join(context.directory, "untracked")
    copy_script(directory)
    pin(directory, hd(context.pins))
    {output, status} = run(directory, context.source)
    assert status != 0
    assert output =~ "needs a git checkout"
  end

  defp init(directory) do
    File.mkdir_p!(directory)
    git!(directory, ["init", "--quiet", "--initial-branch=main"])
    git!(directory, ["config", "user.name", "CAP tests"])
    git!(directory, ["config", "user.email", "cap-tests@example.test"])
  end

  defp copy_script(directory) do
    File.mkdir_p!(Path.join(directory, "scripts"))
    File.cp!("scripts/verifier_source.exs", Path.join(directory, "scripts/verifier_source.exs"))
  end

  defp pin(directory, commit) do
    File.mkdir_p!(Path.join(directory, "priv"))

    File.write!(
      Path.join(directory, "priv/verifier-source.json"),
      JSON.encode!(%{"repository" => "https://cap-verifier.test/repo.git", "commit" => commit})
    )
  end

  defp commit(directory) do
    git!(directory, ["add", "priv/verifier-source.json"])
    git!(directory, ["commit", "--quiet", "-m", "Update verifier pin"])
  end

  defp run(directory, source) do
    System.cmd(
      "elixir",
      [
        "-e",
        "Code.require_file(\"scripts/verifier_source.exs\"); CharterAgreementProtocol.VerifierSource.run([])"
      ],
      cd: directory,
      stderr_to_stdout: true,
      env: [
        {"ERL_FLAGS", "+S 2"},
        {"GIT_CONFIG_COUNT", "3"},
        {"GIT_CONFIG_KEY_0", "url.file://#{source}.insteadOf"},
        {"GIT_CONFIG_VALUE_0", "https://cap-verifier.test/repo.git"},
        {"GIT_CONFIG_KEY_1", "maintenance.auto"},
        {"GIT_CONFIG_VALUE_1", "false"},
        {"GIT_CONFIG_KEY_2", "gc.auto"},
        {"GIT_CONFIG_VALUE_2", "0"}
      ]
    )
  end

  # Throwaway repositories must not start git's detached background maintenance
  # (from git 2.54): it keeps writing into .git and races File.rm_rf!/1 in on_exit.
  @no_maintenance ["-c", "maintenance.auto=false", "-c", "gc.auto=0"]

  defp git!(directory, args) do
    {output, status} =
      System.cmd("git", @no_maintenance ++ args, cd: directory, stderr_to_stdout: true)

    assert status == 0, output
    output
  end
end
