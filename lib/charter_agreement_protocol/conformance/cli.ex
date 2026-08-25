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
    with {:ok, entries} <- regular_entries(root),
         true <- entries != [] and length(entries) <= @maximum_files,
         true <- Enum.sum_by(entries, &elem(&1, 1)) <= @maximum_bytes,
         {:ok, files} <- read_regular_entries(entries, root) do
      {:ok, files}
    else
      _failure -> :error
    end
  rescue
    _exception -> :error
  end

  defp regular_entries(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, entries} ->
      case File.lstat(path) do
        {:ok, %File.Stat{type: :directory}} ->
          {:cont, {:ok, entries}}

        {:ok, %File.Stat{type: :regular, size: size}} ->
          {:cont, {:ok, [{path, size} | entries]}}

        _non_regular_or_fault ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      :error -> :error
    end
  end

  defp read_regular_entries(entries, root) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {path, expected_size}, {:ok, files} ->
      case read_regular(path, expected_size) do
        {:ok, bytes} ->
          relative = Path.relative_to(path, root)
          {:cont, {:ok, Map.put(files, relative, bytes)}}

        :error ->
          {:halt, :error}
      end
    end)
  end

  defp read_regular(path, expected_size) do
    File.open(path, [:read, :binary], fn device ->
      with {:ok, info} <- :file.read_file_info(device),
           true <- elem(info, 2) == :regular and elem(info, 1) == expected_size,
           {:ok, bytes} <- read_exact(device, expected_size) do
        {:ok, bytes}
      else
        _fault_or_changed_file -> :error
      end
    end)
    |> case do
      {:ok, {:ok, bytes}} -> {:ok, bytes}
      _failure -> :error
    end
  end

  defp read_exact(device, expected_size) do
    case IO.binread(device, expected_size + 1) do
      :eof when expected_size == 0 -> {:ok, ""}
      bytes when is_binary(bytes) and byte_size(bytes) == expected_size -> {:ok, bytes}
      _different_size_or_fault -> :error
    end
  end

  defp verify_certified_index(%{"index.json" => bytes}) do
    if Report.index_identity(bytes) == @certified_index_sha256_base64url, do: :ok, else: :error
  end

  defp verify_certified_index(_files), do: :error
end
