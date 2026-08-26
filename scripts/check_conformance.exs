alias CharterAgreementProtocol.Conformance.{Cli, Report}
alias CharterAgreementProtocol.{Conformance.Corpus, RequirementMap}

defmodule CharterAgreementProtocol.ConformanceMatrixGate do
  @root Path.expand("..", __DIR__)
  @matrix_path "spec/requirements.md"
  @mutation_source "scripts/check_conformance_mutations.exs"

  def run do
    rendered = RequirementMap.render_markdown()

    case File.read(Path.join(@root, @matrix_path)) do
      {:ok, contents} when contents == rendered ->
        :ok

      {:ok, _stale} ->
        raise "requirements matrix is stale: regenerate #{@matrix_path} from RequirementMap"

      {:error, _missing} ->
        raise "requirements matrix is missing: render #{@matrix_path} from RequirementMap"
    end

    entries = RequirementMap.entries()

    for {requirement, []} <- entries do
      raise "requirement without evidence: #{requirement}"
    end

    observed_cells =
      corpus_cases()
      |> Enum.frequencies_by(&"#{&1["surface"]}:#{&1["class"]}")
      |> Map.keys()
      |> MapSet.new()

    covered_cells =
      entries
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.flat_map(fn
        {:corpus, cells} -> cells
        _other_evidence -> []
      end)
      |> MapSet.new()

    for cell <- MapSet.to_list(covered_cells), not MapSet.member?(observed_cells, cell) do
      raise "requirement cites a corpus cell that does not exist: #{cell}"
    end

    uncovered = MapSet.difference(observed_cells, covered_cells)

    if MapSet.size(uncovered) > 0 do
      raise "corpus cells without any bound requirement: #{Enum.sort(uncovered) |> Enum.join(", ")}"
    end

    mapped_mutations =
      entries
      |> Enum.flat_map(fn
        {_requirement, evidence} ->
          Enum.flat_map(evidence, fn
            {:mutation, name} -> [name]
            _other_evidence -> []
          end)
      end)
      |> MapSet.new()

    source_mutations =
      @root
      |> Path.join(@mutation_source)
      |> File.read!()
      |> RequirementMap.source_mutation_names()
      |> MapSet.new()

    orphan_mutations = MapSet.difference(source_mutations, mapped_mutations)
    unknown_mutations = MapSet.difference(mapped_mutations, source_mutations)

    if MapSet.size(orphan_mutations) > 0 do
      raise "named source mutations without any bound requirement: #{Enum.sort(orphan_mutations) |> Enum.join(", ")}"
    end

    if MapSet.size(unknown_mutations) > 0,
      do:
        raise(
          "requirements cite unknown mutations: #{Enum.sort(unknown_mutations) |> Enum.join(", ")}"
        )

    cases = length(corpus_cases())

    IO.puts(
      "requirements matrix: fresh requirements=#{length(entries)} corpus_cells=#{MapSet.size(covered_cells)} " <>
        "corpus_cases=#{cases} mutations=#{MapSet.size(mapped_mutations)}"
    )
  end

  defp corpus_cases do
    files =
      "priv/conformance/**/*"
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Map.new(fn path ->
        {Path.relative_to(path, "priv/conformance"), File.read!(path)}
      end)

    case Corpus.load(files) do
      {:ok, corpus} -> corpus.cases
      {:error, reason} -> raise "corpus load failed: #{inspect(reason)}"
    end
  end
end

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
    CharterAgreementProtocol.ConformanceMatrixGate.run()

    IO.puts(
      "conformance verification: certified index #{Report.index_identity(File.read!("priv/conformance/index.json"))}"
    )

  status ->
    Mix.raise("conformance verification exited #{status}")
end
