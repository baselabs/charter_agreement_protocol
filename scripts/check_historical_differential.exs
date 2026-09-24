# Standing per-release semantics certification: run every frozen historical
# certified corpus under the CURRENT package through the pure runner, and
# require verdict agreement except an enumerated per-(tag, case) transition
# allowlist. This is finite evidence over named inputs — the published claim's
# exact scope — never a proof of universal equivalence.
#
#     mix run --no-start scripts/check_historical_differential.exs
#
# The frozen corpora are extracted from their release tags by content into
# memory (never written back — a released index is immutable), loaded through
# the pure loader (which enforces each corpus's own self-digest and the
# extension-registry identity), and executed by the pure runner. A corpus
# that cannot load, a count that differs from its recorded index, a verdict
# that differs without an allowlist entry, or an allowlist entry that no
# longer fires — each fails this gate.

alias CharterAgreementProtocol.Conformance.{Corpus, Runner}

defmodule CharterAgreementProtocol.HistoricalDifferentialGate do
  @moduledoc false

  # The per-(tag, case) deliberate transitions. Every entry names the exact
  # case id and the verdict it carried when frozen vs. under the current
  # package; entries that stop firing fail the gate (a transition that
  # silently disappeared is drift, not compatibility).
  @expected_disagreements %{
    "v0.2.0" => %{
      "descriptor-rev3-fails-closed" => {"protected_header_invalid", "valid"}
    },
    "v0.2.1" => %{
      "descriptor-rev3-fails-closed" => {"protected_header_invalid", "valid"}
    }
  }

  @expected_counts %{
    "v0.1.0" => 85,
    "v0.2.0" => 90,
    "v0.2.1" => 90,
    "v0.3.0" => 100,
    "v0.3.2" => 100
  }

  def run do
    repo = Path.expand("..", __DIR__)

    Enum.each(@expected_counts, fn {tag, expected_count} ->
      files = historical_files(repo, tag)
      with {:ok, corpus} <- Corpus.load(files, true),
           true <- length(corpus.cases) == expected_count,
           results <- Runner.run(corpus) do
        disagreements =
          results
          |> Enum.reject(& &1.agree)
          |> Map.new(&{&1.id, {verdict(&1.expected), verdict(&1.actual)}})

        expected = Map.get(@expected_disagreements, tag, %{})
        unexpected = Map.keys(disagreements) -- Map.keys(expected)
        unfired = Map.keys(expected) -- Map.keys(disagreements)

        cond do
          unexpected != [] ->
            raise "historical differential #{tag}: unexpected verdict transitions #{inspect(Map.take(disagreements, unexpected))}"

          unfired != [] ->
            raise "historical differential #{tag}: allowlist entries no longer firing #{inspect(unfired)}"

          true ->
            drifted =
              Enum.filter(expected, fn {id, pair} -> disagreements[id] != pair end)

            if drifted != [],
              do:
                raise("historical differential #{tag}: transition direction drift #{inspect(drifted)}")

            IO.puts(
              "historical differential: #{tag} #{length(corpus.cases)} cases, #{map_size(expected)} enumerated transition(s)"
            )
        end
      else
        false ->
          raise "historical differential #{tag}: case count drifted from the frozen index"

        {:error, error} ->
          raise "historical differential #{tag}: corpus failed to load under the current package: #{inspect(error, structs: false)}"
      end
    end)
  end

  defp historical_files(repo, tag) do
    index_entry = {"index.json", show(repo, tag, "index.json")}

    case_entries =
      for path <- case_paths(repo, tag) do
        {path, show(repo, tag, path)}
      end

    Map.new([index_entry | case_entries])
  end

  defp case_paths(repo, tag) do
    {out, 0} =
      System.cmd("git", ["ls-tree", "--name-only", "#{tag}:priv/conformance/cases"],
        stderr_to_stdout: true,
        cd: repo
      )

    out
    |> String.split("\n", trim: true)
    |> Enum.map(&"cases/#{&1}")
  end

  defp show(repo, tag, path) do
    {out, 0} =
      System.cmd("git", ["show", "#{tag}:priv/conformance/#{path}"],
        stderr_to_stdout: true,
        cd: repo
      )

    out
  end

  defp verdict(%{"status" => "valid"}), do: "valid"
  defp verdict(%{"status" => "invalid", "error_code" => code}), do: code
end

CharterAgreementProtocol.HistoricalDifferentialGate.run()
