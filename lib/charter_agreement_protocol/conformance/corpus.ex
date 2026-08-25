defmodule CharterAgreementProtocol.Conformance.Corpus do
  @moduledoc """
  Pure conformance-corpus integrity loader.

  `load/1` accepts a `%{relative_path => bytes}` map and performs no I/O. The
  compiled applicability floor, not the index itself, decides which cells are
  required. Counts must equal observations; an empty or all-not-applicable
  corpus cannot load.
  """

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest, Error, Json}

  @index_format "charter-agreement-protocol-conformance-corpus-index"
  @case_format "charter-agreement-protocol-conformance-cases"
  @index_keys ~w(applicability corpus_digest files format total_cases)
  @file_keys ~w(cases path sha256_base64url)
  @case_keys ~w(class expect id input surface)

  @surfaces [
    "base64url.decode",
    "json.decode",
    "canonicalization.encode",
    "digest.hash",
    "schema.validate",
    "party_descriptor.verify",
    "descriptor_chain.verify",
    "charter_revision.decode",
    "acceptance.verify",
    "acceptance.equivocation",
    "termination.verify",
    "chain.verify",
    "governing_revision",
    "receipt.verify"
  ]

  @classes [
    "valid",
    "boundary_near",
    "exact_bound",
    "maximum_plus_one",
    "invalid_encoding",
    "invalid_type",
    "invalid_constraint",
    "invalid_cardinality",
    "unknown_member",
    "missing_required",
    "non_canonical_bytes",
    "digest_mismatch",
    "signature_invalid",
    "chain_invalid",
    "descriptor_superseded",
    "descriptor_fork",
    "equivocation",
    "chain_fork",
    "supersession",
    "precedence_selection",
    "outcome_indeterminate"
  ]

  @floor %{
    "base64url.decode" => %{
      required: ~w(valid exact_bound invalid_encoding),
      n_a: "non-base64url behavior is outside the byte decoder"
    },
    "json.decode" => %{
      required:
        ~w(valid boundary_near exact_bound maximum_plus_one invalid_encoding invalid_type),
      n_a: "schema, canonical-byte, and digest behavior is outside the JSON decoder"
    },
    "canonicalization.encode" => %{
      required: ~w(valid invalid_encoding invalid_type non_canonical_bytes),
      n_a: "decode, schema, and digest behavior is outside canonical encoding"
    },
    "digest.hash" => %{
      required: ~w(valid invalid_type digest_mismatch),
      n_a: "codec and schema behavior is outside tagged digest verification"
    },
    "schema.validate" => %{
      required:
        ~w(valid invalid_type invalid_constraint invalid_cardinality unknown_member missing_required maximum_plus_one),
      n_a: "byte encoding and digest behavior is outside artifact schema validation"
    },
    "party_descriptor.verify" => %{
      required: ~w(valid signature_invalid),
      n_a:
        "set topology and foundational codec-only behavior are outside one descriptor verification"
    },
    "descriptor_chain.verify" => %{
      required: ~w(signature_invalid chain_invalid descriptor_superseded descriptor_fork),
      n_a: "single-artifact and foundational codec-only behavior are outside descriptor topology"
    },
    "charter_revision.decode" => %{
      required:
        ~w(valid invalid_type invalid_constraint invalid_cardinality unknown_member missing_required),
      n_a: "signature, chain, and foundational codec-only behavior are outside revision decoding"
    },
    "acceptance.verify" => %{
      required: ~w(valid invalid_constraint signature_invalid),
      n_a:
        "set-level equivocation and foundational codec-only behavior are outside one acceptance"
    },
    "acceptance.equivocation" => %{
      required: ~w(equivocation),
      n_a:
        "single-artifact and foundational codec-only behavior are outside paired acceptance evidence"
    },
    "termination.verify" => %{
      required: ~w(valid invalid_constraint signature_invalid),
      n_a:
        "governance effects and foundational codec-only behavior are outside one termination notice"
    },
    "chain.verify" => %{
      required: ~w(valid chain_fork supersession),
      n_a: "single-artifact and foundational codec-only behavior are outside set verification"
    },
    "governing_revision" => %{
      required: ~w(precedence_selection),
      n_a: "set integrity and single-artifact behavior are outside temporal precedence selection"
    },
    "receipt.verify" => %{
      required: ~w(valid invalid_constraint signature_invalid chain_fork outcome_indeterminate),
      n_a: "non-receipt codec and set-construction behavior is outside receipt verification"
    }
  }

  @enforce_keys [:index, :index_bytes, :cases, :case_ids, :identity]
  defstruct [:index, :index_bytes, :cases, :case_ids, :identity]

  @type t :: %__MODULE__{
          index: map(),
          index_bytes: binary(),
          cases: [map()],
          case_ids: MapSet.t(binary()),
          identity: binary()
        }

  @doc "The public and codec surfaces present in the compiled applicability floor."
  @spec surfaces() :: [binary()]
  def surfaces, do: @surfaces

  @doc "The case classes present in the compiled applicability floor."
  @spec classes() :: [binary()]
  def classes, do: @classes

  @doc "The independently compiled required-cell and not-applicable policy."
  @spec floor() :: %{binary() => %{required: [binary()], n_a: binary()}}
  def floor, do: @floor

  @doc "Load and integrity-check a complete in-memory corpus."
  @spec load(term()) :: {:ok, t()} | {:error, Error.t()}
  def load(map) when is_map(map) do
    with {:ok, index_bytes} <- fetch_index(map),
         {:ok, index} <- decode_canonical(index_bytes, :index),
         :ok <- validate_index(index),
         :ok <- verify_corpus_digest(index),
         :ok <- reject_empty(index),
         :ok <- verify_file_set(index, map),
         :ok <- verify_hashes(index, map),
         {:ok, cases_by_file} <- load_case_files(index, map),
         :ok <- verify_counts(index, cases_by_file),
         {:ok, cases} <- flatten_valid_cases(cases_by_file),
         :ok <- verify_unique_ids(cases),
         :ok <- verify_applicability(index, cases) do
      {:ok,
       %__MODULE__{
         index: index,
         index_bytes: index_bytes,
         cases: cases,
         case_ids: MapSet.new(cases, & &1["id"]),
         identity: index["corpus_digest"]
       }}
    end
  end

  def load(_map), do: index_error()

  defp fetch_index(map) do
    case Map.get(map, "index.json") do
      bytes when is_binary(bytes) -> {:ok, bytes}
      _other -> index_error()
    end
  end

  defp decode_canonical(bytes, kind) do
    with {:ok, value} <- Json.decode(bytes),
         {:ok, ^bytes} <- Canonicalization.encode(value) do
      {:ok, plain(value)}
    else
      _failure -> if(kind == :index, do: index_error(), else: case_error())
    end
  end

  defp validate_index(index) do
    valid? =
      is_map(index) and sorted_keys(index) == @index_keys and index["format"] == @index_format and
        is_binary(index["corpus_digest"]) and is_integer(index["total_cases"]) and
        index["total_cases"] >= 0 and valid_files?(index["files"]) and
        is_map(index["applicability"])

    if valid?, do: :ok, else: index_error()
  end

  defp valid_files?(files) when is_list(files) do
    files != [] and Enum.all?(files, &valid_file?/1) and
      files |> Enum.map(& &1["path"]) |> then(&(&1 == Enum.uniq(&1)))
  end

  defp valid_files?(_files), do: false

  defp valid_file?(entry) when is_map(entry) do
    sorted_keys(entry) == @file_keys and is_integer(entry["cases"]) and entry["cases"] >= 0 and
      is_binary(entry["sha256_base64url"]) and
      is_binary(entry["path"]) and
      Regex.match?(~r/\Acases\/[a-z0-9][a-z0-9_-]*\.json\z/, entry["path"])
  end

  defp valid_file?(_entry), do: false

  defp verify_corpus_digest(index) do
    without_digest = Map.delete(index, "corpus_digest")

    with {:ok, bytes} <- Canonicalization.encode(tagged(without_digest)),
         digest <- :corpus_index |> Digest.hash(bytes) |> Digest.to_tagged() do
      if digest == index["corpus_digest"], do: :ok, else: index_error()
    end
  end

  defp reject_empty(%{"total_cases" => 0}), do: corpus_empty_error()
  defp reject_empty(_index), do: :ok

  defp verify_file_set(index, map) do
    expected = ["index.json" | Enum.map(index["files"], & &1["path"])] |> Enum.sort()
    observed = map |> Map.keys() |> Enum.sort()
    if expected == observed, do: :ok, else: file_set_error()
  end

  defp verify_hashes(index, map) do
    if Enum.all?(index["files"], fn entry ->
         raw_hash(Map.fetch!(map, entry["path"])) == entry["sha256_base64url"]
       end),
       do: :ok,
       else: hash_error()
  end

  defp load_case_files(index, map) do
    Enum.reduce_while(index["files"], {:ok, []}, fn entry, {:ok, loaded} ->
      case decode_canonical(Map.fetch!(map, entry["path"]), :case) do
        {:ok, %{"format" => @case_format, "cases" => cases} = file}
        when map_size(file) == 2 and is_list(cases) ->
          {:cont, {:ok, [{entry, cases} | loaded]}}

        _failure ->
          {:halt, case_error()}
      end
    end)
    |> then(fn
      {:ok, loaded} -> {:ok, Enum.reverse(loaded)}
      error -> error
    end)
  end

  defp verify_counts(index, cases_by_file) do
    file_counts_match? =
      Enum.all?(cases_by_file, fn {entry, cases} -> entry["cases"] == length(cases) end)

    observed_total = Enum.sum(Enum.map(cases_by_file, fn {_entry, cases} -> length(cases) end))

    if file_counts_match? and index["total_cases"] == observed_total,
      do: :ok,
      else: count_error()
  end

  defp flatten_valid_cases(cases_by_file) do
    cases = Enum.flat_map(cases_by_file, &elem(&1, 1))
    if Enum.all?(cases, &valid_case?/1), do: {:ok, cases}, else: case_error()
  end

  defp valid_case?(one) when is_map(one) do
    sorted_keys(one) == @case_keys and is_binary(one["id"]) and one["id"] != "" and
      one["surface"] in @surfaces and one["class"] in @classes and
      valid_expectation?(one["expect"])
  end

  defp valid_case?(_one), do: false

  defp valid_expectation?(%{"status" => "valid", "output" => _output} = expect),
    do: map_size(expect) == 2

  defp valid_expectation?(%{"status" => "invalid", "error_code" => code} = expect),
    do: map_size(expect) == 2 and is_binary(code) and code != ""

  defp valid_expectation?(_expect), do: false

  defp verify_unique_ids(cases) do
    ids = Enum.map(cases, & &1["id"])
    if ids == Enum.uniq(ids), do: :ok, else: duplicate_id_error()
  end

  defp verify_applicability(index, cases) do
    applicability = index["applicability"]
    observed = Enum.frequencies_by(cases, &{&1["surface"], &1["class"]})

    valid? =
      sorted_keys(applicability) == Enum.sort(@surfaces) and
        Enum.all?(@surfaces, fn surface ->
          cells = applicability[surface]

          is_map(cells) and sorted_keys(cells) == Enum.sort(@classes) and
            valid_cells?(surface, cells, observed)
        end)

    if valid?, do: :ok, else: applicability_error()
  end

  defp valid_cells?(surface, cells, observed) do
    floor = Map.fetch!(@floor, surface)

    Enum.all?(@classes, fn class ->
      count = Map.get(observed, {surface, class}, 0)

      if class in floor.required do
        is_integer(cells[class]) and cells[class] > 0 and cells[class] == count
      else
        cell = cells[class]

        is_map(cell) and map_size(cell) == 1 and
          match?(%{"n_a" => reason} when is_binary(reason) and reason != "", cell) and count == 0
      end
    end)
  end

  defp sorted_keys(map), do: map |> Map.keys() |> Enum.sort()
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

  defp plain({:object, members}),
    do: Map.new(members, fn {key, value} -> {key, plain(value)} end)

  defp index_error, do: {:error, Error.new(:corpus_index_invalid, ["corpus", "index"])}
  defp case_error, do: {:error, Error.new(:corpus_case_invalid, ["corpus", "cases"])}
  defp hash_error, do: {:error, Error.new(:corpus_hash_mismatch, ["corpus", "files"])}

  defp file_set_error,
    do: {:error, Error.new(:corpus_file_set_mismatch, ["corpus", "files"])}

  defp duplicate_id_error,
    do: {:error, Error.new(:corpus_case_id_duplicate, ["corpus", "cases"])}

  defp count_error, do: {:error, Error.new(:corpus_count_mismatch, ["corpus", "counts"])}

  defp applicability_error,
    do: {:error, Error.new(:corpus_applicability_incomplete, ["corpus", "applicability"])}

  defp corpus_empty_error,
    do: {:error, Error.new(:corpus_empty, ["corpus", "total_cases"])}
end
