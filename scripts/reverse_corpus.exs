defmodule CharterAgreementProtocol.ReverseCorpus do
  @moduledoc false

  alias CharterAgreementProtocol.Conformance.{Corpus, Runner}

  def load!(root) do
    cases_dir = Path.join(root, "cases")

    files =
      cases_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Map.new(fn name ->
        {Path.join("cases", name), File.read!(Path.join(cases_dir, name))}
      end)
      |> Map.put("index.json", File.read!(Path.join(root, "index.json")))

    {:ok, corpus} = Corpus.load(files)
    corpus
  end

  def checked!(corpus) do
    corpus |> Runner.run() |> Map.new(&checked_outcome!/1)
  end

  def published!(frozen, cases) do
    fresh = Enum.map(frozen.cases, &Map.update!(&1, "id", fn id -> "dispatch-" <> id end))
    checked!(%{frozen | cases: fresh})

    # The candidate loader has validated the case envelopes. Let the
    # published runner report its own fallback for unfamiliar operations.
    %{frozen | cases: cases}
    |> Runner.run()
    |> Map.new(&outcome/1)
  end

  def with_public_probes(corpus_outcomes, probes) do
    public_outcomes = Map.new(probes, fn {id, result} -> {"public_api/" <> id, result} end)
    Map.merge(corpus_outcomes, public_outcomes)
  end

  # Both runtimes use the same projections. Carry them across the process
  # boundary without converting native terms to JSON.
  def write_outcomes!(path, outcomes), do: File.write!(path, :erlang.term_to_binary(outcomes))

  def read_outcomes!(path), do: path |> File.read!() |> :erlang.binary_to_term([:safe])

  def observation(operation, value), do: %{"operation" => operation, "value" => value}

  defp checked_outcome!(%{agree: true} = result), do: outcome(result)

  defp checked_outcome!(%{id: id, actual: actual, expected: expected}) do
    raise "corpus case #{id}: observed #{inspect(actual)}, expected #{inspect(expected)}"
  end

  defp outcome(%{id: id, surface: surface, actual: %{"status" => "valid"} = actual}),
    do: {qualified(id), observation(surface, actual)}

  defp outcome(%{
         id: id,
         surface: surface,
         actual: %{"status" => "invalid", "error_code" => code}
       }) do
    {qualified(id), observation(surface, code)}
  end

  defp qualified(id), do: "corpus_runner/" <> id
end
