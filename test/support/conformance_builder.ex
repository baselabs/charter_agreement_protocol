defmodule CharterAgreementProtocol.ConformanceTest.Builder do
  @moduledoc false

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest, ExtensionRegistry}
  alias CharterAgreementProtocol.Conformance.Corpus

  @case_format "charter-agreement-protocol-conformance-cases"
  @index_format "charter-agreement-protocol-conformance-corpus-index"

  def minimal_cases do
    for surface <- Corpus.surfaces(),
        class <- Corpus.floor() |> Map.fetch!(surface) |> Map.fetch!(:required) do
      %{
        "id" => String.replace(surface <> "-" <> class, ".", "-"),
        "surface" => surface,
        "class" => class,
        "input" => %{
          "fixture" => surface <> ":" <> class,
          "null_value" => nil,
          "boolean_value" => true,
          "float_value" => 1.5
        },
        "expect" => expectation(class)
      }
    end
  end

  def build(cases \\ minimal_cases()) do
    case_bytes = canonical!(%{"format" => @case_format, "cases" => cases})
    path = "cases/foundation.json"

    index = %{
      "format" => @index_format,
      "corpus_digest" => "",
      "registry_digest" => ExtensionRegistry.digest() |> Digest.to_tagged(),
      "total_cases" => length(cases),
      "files" => [
        %{
          "path" => path,
          "sha256_base64url" => raw_hash(case_bytes),
          "cases" => length(cases)
        }
      ],
      "applicability" => applicability(cases)
    }

    index = Map.put(index, "corpus_digest", corpus_digest(index))
    %{"index.json" => canonical!(index), path => case_bytes}
  end

  def update_index(map, update, options \\ []) do
    index = map |> Map.fetch!("index.json") |> decode!() |> update.()
    index = if Keyword.get(options, :redigest, true), do: redigest(index), else: index
    Map.put(map, "index.json", canonical!(index))
  end

  def update_cases(map, update) do
    path = "cases/foundation.json"
    case_file = map |> Map.fetch!(path) |> decode!()
    case_file = Map.update!(case_file, "cases", update)
    case_bytes = canonical!(case_file)

    map
    |> Map.put(path, case_bytes)
    |> update_index(fn index ->
      cases = case_file["cases"]

      index
      |> Map.put("total_cases", length(cases))
      |> Map.put("applicability", applicability(cases))
      |> Map.update!("files", fn [entry] ->
        [%{entry | "cases" => length(cases), "sha256_base64url" => raw_hash(case_bytes)}]
      end)
    end)
  end

  def replace_case_file(map, case_file) do
    path = "cases/foundation.json"
    bytes = canonical!(case_file)

    map
    |> Map.put(path, bytes)
    |> update_index(fn index ->
      Map.update!(index, "files", fn [entry] ->
        [%{entry | "sha256_base64url" => raw_hash(bytes)}]
      end)
    end)
  end

  def decode!(bytes) do
    {:ok, value} = CharterAgreementProtocol.Json.decode(bytes)
    plain(value)
  end

  def canonical!(plain) do
    {:ok, bytes} = Canonicalization.encode(tagged(plain))
    bytes
  end

  def corpus_digest(index) do
    index
    |> Map.delete("corpus_digest")
    |> canonical!()
    |> then(&Digest.hash(:corpus_index, &1))
    |> Digest.to_tagged()
  end

  defp redigest(index), do: Map.put(index, "corpus_digest", corpus_digest(index))

  defp applicability(cases) do
    observed = Enum.frequencies_by(cases, &{&1["surface"], &1["class"]})

    Map.new(Corpus.surfaces(), fn surface ->
      floor = Map.fetch!(Corpus.floor(), surface)

      cells =
        Map.new(Corpus.classes(), fn class ->
          {class, applicability_cell(surface, class, floor, observed)}
        end)

      {surface, cells}
    end)
  end

  defp applicability_cell(surface, class, floor, observed) do
    if class in floor.required,
      do: Map.get(observed, {surface, class}, 0),
      else: %{"n_a" => floor.n_a}
  end

  defp expectation("valid"), do: %{"status" => "valid", "output" => %{"accepted" => true}}
  defp expectation(_class), do: %{"status" => "invalid", "error_code" => "invalid_type"}

  defp raw_hash(bytes), do: bytes |> Digest.of() |> Map.fetch!(:bytes) |> Base64Url.encode()

  defp tagged(nil), do: :null
  defp tagged(value) when is_boolean(value), do: {:boolean, value}
  defp tagged(value) when is_integer(value), do: {:integer, value}
  defp tagged(value) when is_float(value), do: {:float, value}
  defp tagged(value) when is_binary(value), do: {:string, value}
  defp tagged(value) when is_list(value), do: {:array, Enum.map(value, &tagged/1)}

  defp tagged(value) when is_map(value),
    do: {:object, Enum.map(value, fn {key, item} -> {key, tagged(item)} end)}

  defp plain(:null), do: nil
  defp plain({:boolean, value}), do: value
  defp plain({:integer, value}), do: value
  defp plain({:float, value}), do: value
  defp plain({:string, value}), do: value
  defp plain({:array, values}), do: Enum.map(values, &plain/1)
  defp plain({:object, members}), do: Map.new(members, fn {key, value} -> {key, plain(value)} end)
end
