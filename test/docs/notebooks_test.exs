defmodule CharterAgreementProtocol.Docs.NotebooksTest do
  @moduledoc """
  Runs each notebook in `docs/notebooks` from top to bottom, so a notebook that stops
  working fails the suite.

  The test reads a notebook's Elixir cells in order and points its `Mix.install` at this
  checkout instead of the Hex release. It then evaluates the cells one at a time in a
  separate `elixir` process, carrying variables and aliases from cell to cell the way
  Livebook does, and prints each cell's result for the assertions below.

  Network: the notebooks install the matching 1.0 signer from Hex.
  `CAP_DOCS_SIGNER_PATH` may select real matching source during coordinated release
  preparation; the evaluated application version must still be 1.0.0. When neither the
  `Mix.install` cache nor the local Hex package cache holds it, the first run needs network
  access; later runs reuse the cache. Offline, `mix test --exclude notebooks` skips this
  file.

  `CAP_NOTEBOOKS_DIR` points the test at another directory of notebooks. It exists so a
  broken copy can be run to show the test fails; leave it unset otherwise.
  """

  use ExUnit.Case, async: false

  @moduletag :notebooks
  @moduletag timeout: :timer.minutes(10)

  @root Path.expand("../..", __DIR__)
  # The notebooks install the release they ship in.
  @hex_dependency ~s({:charter_agreement_protocol, "~> #{Mix.Project.config()[:version]}"})

  # Evaluates cell_*.exs in order with one binding and one environment, then prints
  # each result under a marker line.
  @runner ~S"""
  [dir] = System.argv()

  dir
  |> Path.join("cell_*.exs")
  |> Path.wildcard()
  |> Enum.sort()
  |> Enum.reduce({[], Code.env_for_eval([])}, fn path, {binding, env} ->
    quoted = path |> File.read!() |> Code.string_to_quoted!(file: path)
    {value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
    IO.puts("== #{Path.basename(path, ".exs")}")
    IO.inspect(value, limit: :infinity, printable_limit: :infinity, width: 120)
    {binding, env}
  end)
  """

  test "charter-tour runs from top to bottom" do
    output = run_notebook!("charter-tour.livemd")

    assert output =~ ~s(name: "ML-DSA-65")
    assert output =~ ~r/name: "Ed25519"[^}]*verifiable: true/
    assert output =~ ~s(["issuer-key", "acceptor-key"])
    assert output =~ "topology: :linear"
    assert output =~ "chain_topology: :linear"
    assert output =~ "before_effective_from: {:ok, :none}"
    assert output =~ ~r/at_effective_from: \{:ok,\s*"sha-256:[\w-]{43}"\}/
    assert output =~ "governing_match: :match"
    assert output =~ "deployment_digest_matched: true"
    assert output =~ "code: :signature_invalid"

    floor = CharterAgreementProtocol.Facts.not_verified_floor()
    assert length(floor) == 12
    assert String.replace(output, ~r/\s+/, " ") =~ inspect(floor)
  end

  test "fork-repair runs from top to bottom" do
    output = run_notebook!("fork-repair.livemd")

    assert output =~ "code: :signing_refused"
    assert output =~ "kind: :acceptance_equivocation"
    assert output =~ "winner: nil"
    assert output =~ "{:ok, :contested}"
    assert output =~ "governing_match: :undetermined"
    assert output =~ "chain_conflict: :none"
    assert output =~ "equals_repair: true"
  end

  test "each notebook's first cell is a Livebook setup cell" do
    for path <- notebooks() do
      source = File.read!(path)
      [before_first_section | _rest] = String.split(source, ~r/^## /m, parts: 2)

      assert before_first_section =~ ~r/^# .+\n/,
             "#{path} must start with a # title"

      assert [setup | _cells] = cells(source)

      assert before_first_section =~ setup,
             "#{path}: the setup cell must sit under the title, before the first ## section"

      assert setup =~ "Mix.install(" and setup =~ @hex_dependency,
             "#{path}: the setup cell must install #{@hex_dependency}"

      refute source =~ "livebook:{\"file_entities\""
      refute source =~ ~s("EdDSA"), "#{path}: new artifacts use the Ed25519 header"
    end
  end

  defp notebooks do
    dir = System.get_env("CAP_NOTEBOOKS_DIR", Path.join(@root, "docs/notebooks"))
    dir |> Path.join("*.livemd") |> Path.wildcard() |> Enum.sort()
  end

  defp run_notebook!(name) do
    path = Enum.find(notebooks(), &(Path.basename(&1) == name)) || flunk("#{name} not found")
    [setup | rest] = path |> File.read!() |> cells()

    assert setup =~ @hex_dependency
    local = ~s({:charter_agreement_protocol, path: #{inspect(@root)}, override: true})

    work = Path.join(System.tmp_dir!(), "cap-notebook-#{System.unique_integer([:positive])}")
    File.mkdir_p!(work)
    on_exit(fn -> File.rm_rf!(work) end)

    setup = String.replace(setup, @hex_dependency, local)
    run_cells!(name, [matching_signer(setup) | rest], work)
  end

  test "the getting-started tutorial executes its shipped corpus and promised answers" do
    output = run_guide!("getting-started.md", false)
    assert output =~ "chain_topology: :linear"
    assert output =~ ~s({"acceptor", "acceptor-key", "EdDSA", 1})
    assert output =~ "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"
    assert output =~ "{:ok, :none}"
    assert output =~ "code: :chain_invalid"
  end

  test "the producer tutorial executes with the matching signer and exact published digests" do
    output = run_guide!("produce-and-verify.md", true)
    assert output =~ "sha-256:UmFN7RFO8DhZfE-Px9DTAagN-PYLNjIUkIxuyAhjLL4"
    assert output =~ "sha-256:406Y70xTrD7R5amwdDU2C_GZUeVsmjS4xRd40TZAHXE"
    assert output =~ "sha-256:uVgklHrU2JxmE-Mx8dOrmr1Wk8A2PmM-SxoPSbKMYSc"
    assert output =~ "{:error, {:refused, :signing_refused}}"
    assert output =~ ~s({"issuer", "issuer-key-1", "Ed25519", 2})
    assert output =~ "\ntrue\n"
    assert output =~ ":signing_key_mismatch"
  end

  defp run_guide!(name, signer?) do
    source = File.read!(Path.join(@root, "docs/guides/#{name}"))
    [install | rest] = cells(source)
    assert install =~ @hex_dependency
    if signer?, do: assert(install =~ ~s({:charter_agreement_signer, "~> 1.0.0"}))

    dependencies = ~s({:charter_agreement_protocol, path: #{inspect(@root)}, override: true})
    signer = if signer?, do: ~s(, {:charter_agreement_signer, "~> 1.0.0"}), else: ""
    setup = matching_signer("Mix.install([" <> dependencies <> signer <> "])")
    work = Path.join(System.tmp_dir!(), "cap-guide-#{System.unique_integer([:positive])}")
    File.mkdir_p!(work)
    on_exit(fn -> File.rm_rf!(work) end)
    run_cells!(name, [setup | rest], work)
  end

  defp matching_signer(setup) do
    dependency = ~s({:charter_agreement_signer, "~> 1.0.0"})

    setup =
      case System.get_env("CAP_DOCS_SIGNER_PATH") do
        nil ->
          setup

        path ->
          String.replace(
            setup,
            dependency,
            ~s({:charter_agreement_signer, path: #{inspect(Path.expand(path))}})
          )
      end

    setup <>
      ~S"""

      for app <- [:charter_agreement_protocol, :charter_agreement_signer],
          version = Application.spec(app, :vsn), version != nil do
        unless to_string(version) == "1.0.0", do: raise("documentation dependency version drift")
      end
      """
  end

  defp run_cells!(name, blocks, work) do
    blocks
    |> Enum.with_index(1)
    |> Enum.each(fn {cell, index} ->
      File.write!(Path.join(work, "cell_#{String.pad_leading("#{index}", 3, "0")}.exs"), cell)
    end)

    runner = Path.join(work, "runner.exs")
    File.write!(runner, @runner)

    {output, status} =
      System.cmd("elixir", [runner, work],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", nil}]
      )

    assert status == 0, "#{name} failed:\n#{output}"
    output
  end

  defp cells(source) do
    ~r/^```elixir\n(.*?)^```$/ms
    |> Regex.scan(source, capture: :all_but_first)
    |> List.flatten()
  end
end
