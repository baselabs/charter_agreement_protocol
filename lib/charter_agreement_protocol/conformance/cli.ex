defmodule CharterAgreementProtocol.Conformance.Cli do
  @moduledoc """
  CAP never authorizes.

  Filesystem adapter for the pure corpus loader, runner, and report. The CLI
  accepts only an explicit corpus directory and refuses bytes whose raw index
  identity is not the certified release identity.
  """

  alias CharterAgreementProtocol.Conformance.{Corpus, Report, Runner}

  @certified_index_sha256_base64url "NiSzeS8F0SXS6ddeeQhOBdsG4BQn8jcxb8DSX1q-oLM"
  @maximum_files 64
  @maximum_bytes 33_554_432

  @doc "Run conformance verification and return a process exit status."
  @spec run([binary()]) :: 0 | 1 | 2
  def run(["--corpus", root]) do
    with {:ok, files} <- read_files(root),
         :ok <- verify_certified_index(files),
         {:ok, corpus} <- Corpus.load(files),
         results <- Runner.run(corpus),
         {:ok, bytes} <- Report.to_bytes(corpus, results) do
      IO.puts(bytes)
      Report.build(corpus, results).exit_status
    else
      _failure ->
        IO.puts(:stderr, "conformance verification failed")
        1
    end
  end

  def run(_arguments) do
    IO.puts(:stderr, "usage: charter_agreement_protocol --corpus DIRECTORY")
    2
  end

  defp read_files(root) do
    paths = root |> Path.join("**/*") |> Path.wildcard() |> Enum.reject(&File.dir?/1)

    if paths != [] and length(paths) <= @maximum_files do
      files = Map.new(paths, fn path -> {Path.relative_to(path, root), File.read!(path)} end)

      if files |> Map.values() |> Enum.sum_by(&byte_size/1) <= @maximum_bytes,
        do: {:ok, files},
        else: :error
    else
      :error
    end
  rescue
    _exception -> :error
  end

  defp verify_certified_index(%{"index.json" => bytes}) do
    if Report.index_identity(bytes) == @certified_index_sha256_base64url, do: :ok, else: :error
  end

  defp verify_certified_index(_files), do: :error
end
