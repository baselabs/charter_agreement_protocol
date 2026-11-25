defmodule CharterAgreementProtocol.ReverseCorpus do
  @moduledoc false

  alias CharterAgreementProtocol.Conformance.{Corpus, Runner}

  def load!(root) do
    files =
      root
      |> Path.join("{index.json,cases/*.json}")
      |> Path.wildcard()
      |> Map.new(&{Path.relative_to(&1, root), File.read!(&1)})

    {:ok, corpus} = Corpus.load(files)
    corpus
  end

  def checked!(corpus) do
    corpus |> Runner.run() |> Map.new(&checked_outcome!/1)
  end

  def published!(frozen, cases) do
    fresh = Enum.map(frozen.cases, &Map.update!(&1, "id", fn id -> "dispatch-" <> id end))
    checked!(%{frozen | cases: fresh})

    supported_surfaces = MapSet.new(Corpus.surfaces())

    {supported, unsupported} =
      Enum.split_with(cases, &supported?(&1, supported_surfaces))

    observed =
      %{frozen | cases: supported}
      |> Runner.run()
      |> Map.new(&outcome/1)

    Map.merge(observed, Map.new(unsupported, &{qualified(&1["id"]), "unsupported"}))
  end

  def with_public_probes(corpus_outcomes, probes) do
    public_outcomes = Map.new(probes, fn {id, code} -> {"public_api/" <> id, code} end)
    Map.merge(corpus_outcomes, public_outcomes)
  end

  # The published corpus interface lacks exactly these two known entry shapes.
  defp supported?(%{"surface" => "descriptor_publication.verify"}, _surfaces), do: false

  defp supported?(
         %{"surface" => "signing.prepare", "input" => %{"kind" => "party_replacement"}},
         _surfaces
       ),
       do: false

  defp supported?(%{"surface" => surface}, surfaces) do
    unless MapSet.member?(surfaces, surface) do
      raise "missing published dispatch for #{surface}"
    end

    true
  end

  defp checked_outcome!(%{agree: true} = result), do: outcome(result)

  defp checked_outcome!(%{id: id, actual: actual, expected: expected}) do
    raise "corpus case #{id}: observed #{inspect(actual)}, expected #{inspect(expected)}"
  end

  defp outcome(%{id: id, actual: %{"status" => "valid"}}), do: {qualified(id), "valid"}

  defp outcome(%{id: id, actual: %{"status" => "invalid", "error_code" => code}}),
    do: {qualified(id), code}

  defp qualified(id), do: "corpus_runner/" <> id
end
