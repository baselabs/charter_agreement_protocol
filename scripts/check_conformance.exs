alias CharterAgreementProtocol.Conformance.{Cli, Report}

alias CharterAgreementProtocol.{
  Base64Url,
  Conformance.Corpus,
  Conformance.Report,
  Conformance.Runner,
  Json,
  RequirementMap
}

alias AgentBlueprintProtocol.Schema, as: WireGrammar

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

defmodule CharterAgreementProtocol.ConformanceSchemaGate do
  @root Path.expand("..", __DIR__)
  @schema_root "spec/schemas"
  @corpus_root "priv/conformance"

  @expected_schemas [
    "acceptance-claims",
    "charter-revision-claims",
    "compact-jws-protected-header",
    "corpus-index",
    "corpus-report",
    "extension-envelope",
    "party-descriptor-claims",
    "receipt-claims",
    "tagged-digest",
    "termination-claims",
    "timestamp"
  ]

  @claims_schema %{
    "cap+party" => "party-descriptor-claims",
    "cap+acceptance" => "acceptance-claims",
    "cap+termination" => "termination-claims",
    "cap+receipt" => "receipt-claims"
  }

  @typ_names Map.keys(@claims_schema)

  @artifact_surfaces [
    "acceptance.equivocation",
    "acceptance.verify",
    "chain.verify",
    "charter_revision.decode",
    "descriptor_chain.verify",
    "party_descriptor.verify",
    "receipt.verify",
    "termination.verify"
  ]

  @artifact_sources %{
    "acceptance-claims" => "lib/charter_agreement_protocol/acceptance.ex",
    "charter-revision-claims" => "lib/charter_agreement_protocol/charter_revision.ex",
    "party-descriptor-claims" => "lib/charter_agreement_protocol/party_descriptor.ex",
    "receipt-claims" => "lib/charter_agreement_protocol/receipt.ex",
    "termination-claims" => "lib/charter_agreement_protocol/termination_notice.ex"
  }

  def run do
    schemas = load_schemas()
    member_census(schemas)
    closure_census(schemas)

    seeds =
      Map.new(build_seeds(), fn {name, seed} ->
        {name, complete(schema_document(schemas, name), seed)}
      end)

    {seed_positives, negatives} =
      Enum.reduce(schemas, {0, 0}, fn {name, document, parsed}, {positives, count} ->
        seed = Map.fetch!(seeds, name)
        assert_valid(name, "completed seed", parsed, seed)

        emitted =
          document
          |> defects(document, seed, [])
          |> Enum.map(fn {label, operation} = defect ->
            defective = apply_defect(seed, operation)
            assert_invalid(name, label, parsed, defective)
            defect
          end)
          |> length()

        {positives + 1, count + emitted}
      end)

    corpus_positives = validate_corpus_artifacts(schemas)

    IO.puts(
      "wire schemas: ok schemas=#{length(schemas)} seeds=#{seed_positives} " <>
        "corpus_positives=#{corpus_positives} negatives=#{negatives}"
    )
  end

  ## Schema loading — resolved once per run

  defp load_schemas do
    paths = @schema_root |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()
    names = Enum.map(paths, &Path.basename(&1, ".json"))

    if names != @expected_schemas do
      raise "wire schema set diverges: #{inspect(names)}"
    end

    for path <- paths do
      document = @root |> Path.join(path) |> File.read!() |> decode!

      case WireGrammar.parse(document, WireGrammar.dialect()) do
        {:ok, parsed} ->
          {Path.basename(path, ".json"), document, parsed}

        {:error, reason} ->
          raise "wire schema does not parse: #{path} (#{inspect(reason)})"
      end
    end
  end

  defp schema_document(schemas, name) do
    {^name, document, _parsed} = List.keyfind(schemas, name, 0)
    document
  end

  defp schema_for(schemas, name) do
    {^name, _document, parsed} = List.keyfind(schemas, name, 0)
    parsed
  end

  ## Completeness floors — a weakened schema must red, not merely shrink

  # Every artifact claim schema declares exactly the member set and required
  # set of the compiled codec definition it serves.
  defp member_census(schemas) do
    Enum.each(@artifact_sources, fn {schema_name, source_path} ->
      {^schema_name, document, _parsed} = List.keyfind(schemas, schema_name, 0)

      declared = declared_fields(source_path)
      properties = document |> properties_of() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      required = document |> schema_member("required") |> member_names() |> Enum.sort()

      unless properties == Enum.map(declared, &elem(&1, 0)) |> Enum.sort() do
        raise "wire schema members diverge from the codec definition: #{schema_name}\n" <>
                "schema: #{inspect(properties)}\ncodec: #{inspect(Enum.map(declared, &elem(&1, 0)))}"
      end

      unless required ==
               Enum.filter(declared, &elem(&1, 1)) |> Enum.map(&elem(&1, 0)) |> Enum.sort() do
        raise "wire schema required set diverges from the codec definition: #{schema_name}"
      end
    end)
  end

  # Every schema object that names properties is closed — the wire grammar
  # has no open member sets.
  defp closure_census(schemas) do
    Enum.each(schemas, fn {name, document, _parsed} ->
      assert_closed(name, document)
    end)
  end

  defp assert_closed(name, {:object, members}) do
    if List.keyfind(members, "properties", 0) != nil and
         List.keyfind(members, "additionalProperties", 0) !=
           {"additionalProperties", {:boolean, false}} do
      raise "wire schema object with properties is not closed: #{name}"
    end

    Enum.each(members, fn {_key, value} -> assert_closed(name, value) end)
  end

  defp assert_closed(_name, {:array, items}), do: Enum.each(items, &assert_closed(_name, &1))
  defp assert_closed(_name, _scalar), do: :ok

  # AST extraction of the module's @definition Schema.field declarations —
  # the same technique as RequirementMap.source_mutation_names/1.
  defp declared_fields(source_path) do
    {_ast, fields} =
      source_path
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:@, _, [{:definition, _, [definition_call]}]} = node, acc ->
          case definition_call do
            {{:., _, [{:__aliases__, _, [:Schema]}, :definition]}, _,
             [_name, field_calls | _rest]} ->
              {node, field_calls |> field_calls() |> Enum.concat(acc)}

            _other_call ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    fields
  end

  defp field_calls(field_calls) do
    Enum.flat_map(field_calls, fn
      {{:., _, [{:__aliases__, _, [:Schema]}, :field]}, _, [name, options]} = node ->
        required? =
          case List.keyfind(options, :required?, 0) do
            {:required?, true} -> true
            _absent_or_false -> false
          end

        [{literal_string(name), required?}]

      _other ->
        []
    end)
  end

  defp literal_string(literal) when is_binary(literal), do: literal

  ## Seeds — live corpus and report documents

  defp build_seeds do
    descriptor = case_compact("party_descriptor-verify.json", 0)
    acceptance = case_compact("acceptance-verify.json", 0)
    receipt = case_compact("receipt-verify.json", 5)

    [
      {"party-descriptor-claims", compact_payload(descriptor)},
      {"acceptance-claims", compact_payload(acceptance)},
      {"charter-revision-claims", case_revision_text("charter_revision-decode.json", 0)},
      {"termination-claims", compact_payload(case_compact("termination-verify.json", 0))},
      {"receipt-claims", compact_payload(receipt)},
      {"extension-envelope", member!(compact_payload(receipt), "extensions")},
      {"compact-jws-protected-header", compact_protected(descriptor)},
      {"tagged-digest", member!(compact_payload(receipt), "revision_digest")},
      {"timestamp", member!(compact_payload(receipt), "recorded_at")},
      {"corpus-index", corpus_file!("index.json")},
      {"corpus-report", report_document()}
    ]
  end

  defp report_document do
    {:ok, corpus} = corpus_files() |> Corpus.load()
    results = Runner.run(corpus)
    {:ok, bytes} = Report.to_bytes(corpus, results)
    decode!(bytes)
  end

  ## Positive sweep — every valid corpus artifact plus both wire documents

  defp validate_corpus_artifacts(schemas) do
    header = schema_for(schemas, "compact-jws-protected-header")

    wires =
      for path <- corpus_case_paths(),
          {:object, file_members} <- [corpus_file!(path)],
          {"cases", {:array, cases}} <- [List.keyfind(file_members, "cases", 0)],
          {:object, _members} = case_value <- cases,
          valid_case?(case_value),
          surface_of(case_value) in @artifact_surfaces,
          wire <- collect_wire_values(input_of(case_value)) do
        wire
      end

    pairs =
      for wire <- wires do
        case wire do
          {:header, value} -> {header, value}
          {:claims, typ, value} -> {schema_for(schemas, Map.fetch!(@claims_schema, typ)), value}
          {:revision_text, value} -> {schema_for(schemas, "charter-revision-claims"), value}
        end
      end ++
        [
          {schema_for(schemas, "corpus-index"), corpus_file!("index.json")},
          {schema_for(schemas, "corpus-report"), report_document()}
        ]

    Enum.each(pairs, fn {parsed, instance} ->
      assert_valid("corpus artifact", "positive", parsed, instance)
    end)

    length(pairs)
  end

  defp collect_wire_values(value) do
    case value do
      {:string, text} ->
        case String.split(text, ".") do
          [protected, payload, _signature] ->
            case {decode_segment(protected), decode_segment(payload)} do
              {{:object, members} = header, {:object, _} = claims} ->
                case List.keyfind(members, "typ", 0) do
                  {_, {:string, typ}} when typ in @typ_names ->
                    [{:header, header}, {:claims, typ, claims}]

                  _other_typ ->
                    revision_or_none(text)
                end

              _undecodable ->
                revision_or_none(text)
            end

          _not_compact ->
            revision_or_none(text)
        end

      {:array, items} ->
        Enum.flat_map(items, &collect_wire_values/1)

      {:object, members} ->
        Enum.flat_map(members, fn {_name, item} -> collect_wire_values(item) end)

      _scalar ->
        []
    end
  end

  defp revision_or_none(text) do
    case Json.decode(text) do
      {:ok, {:object, _} = value} -> [{:revision_text, value}]
      _not_an_object -> []
    end
  end

  defp decode_segment(segment) do
    case Base64Url.decode(segment) do
      {:ok, bytes} ->
        case Json.decode(bytes) do
          {:ok, value} -> value
          _other -> :undecodable
        end

      _other ->
        :undecodable
    end
  end

  ## Seed completion — inject grammar-valid values for absent optional members

  defp complete(document, seed), do: complete_node(document, document, seed)

  defp complete_node(document, node, instance) do
    node = resolve(document, node)

    case {node, instance} do
      {{:object, _} = schema, {:object, members}} ->
        subs = properties_of(schema)

        injected =
          for {name, sub} <- subs,
              List.keyfind(members, name, 0) == nil,
              do: {name, derive(document, sub)}

        {:object,
         Enum.map(members ++ injected, fn {name, value} ->
           case List.keyfind(subs, name, 0) do
             {^name, sub} -> {name, complete_node(document, sub, value)}
             nil -> {name, value}
           end
         end)}

      {{:object, _} = schema, {:array, items}} ->
        case schema_member(schema, "items") do
          nil ->
            instance

          items_sub ->
            {:array, Enum.map(items, &complete_node(document, items_sub, &1))}
        end

      _scalar_instance ->
        instance
    end
  end

  defp derive(document, sub) do
    sub = resolve(document, sub)

    cond do
      member = schema_member(sub, "enum") ->
        {:array, [first | _]} = member
        first

      member = schema_member(sub, "const") ->
        member

      true ->
        case schema_member(sub, "oneOf") do
          {:array, [first | _]} -> derive(document, first)
          _absent -> derive_typed(document, sub)
        end
    end
  end

  defp derive_typed(document, sub) do
    case schema_member(sub, "type") do
      {:string, name} -> derive_for_type(document, sub, name)
      {:array, [first | _]} -> derive_for_type(document, sub, elem(first, 1))
      _absent -> {:object, []}
    end
  end

  defp derive_for_type(_document, sub, "integer"), do: {:integer, minimum_of(sub, 1)}
  defp derive_for_type(_document, _sub, "number"), do: {:integer, 1}
  defp derive_for_type(_document, _sub, "boolean"), do: {:boolean, true}
  defp derive_for_type(_document, _sub, "null"), do: :null

  defp derive_for_type(_document, sub, "string") do
    lo = sub |> schema_member("minLength") |> unwrap_integer() |> max(1)
    hi = sub |> schema_member("maxLength") |> unwrap_integer()
    length = if hi == nil, do: lo, else: min(lo, hi)
    {:string, String.duplicate("x", length)}
  end

  defp derive_for_type(document, sub, "array") do
    count = sub |> schema_member("minItems") |> unwrap_integer() || 0

    filler =
      case schema_member(sub, "items") do
        nil -> :null
        items_sub -> derive(document, items_sub)
      end

    {:array, List.duplicate(filler, count)}
  end

  defp derive_for_type(document, sub, "object") do
    subs = sub |> properties_of()

    members =
      for name <- sub |> schema_member("required") |> member_names() do
        case List.keyfind(subs, name, 0) do
          nil -> {name, {:boolean, true}}
          {^name, property_sub} -> {name, derive(document, property_sub)}
        end
      end

    {:object, members}
  end

  ## Per-constraint one-defect generation

  defp defects(document, node, instance, path) do
    node = resolve(document, node)
    object_defects(document, node, instance, path) ++ scalar_defects(document, node, path)
  end

  defp object_defects(document, schema, instance, path) do
    case instance do
      {:object, members} ->
        required_drops(schema, path) ++
          closure_defect(schema, path) ++
          property_defects(document, schema, members, path) ++
          additional_defects(document, schema, members, path)

      {:array, [first | _rest]} ->
        case schema_member(schema, "items") do
          nil -> []
          items_sub -> defects(document, items_sub, first, path ++ [0])
        end

      _scalar ->
        []
    end
  end

  defp required_drops(schema, path) do
    schema
    |> schema_member("required")
    |> member_names()
    |> Enum.map(fn name -> {"required:#{name}", {:delete, path ++ [name]}} end)
  end

  defp closure_defect(schema, path) do
    case schema_member(schema, "additionalProperties") do
      {:boolean, false} ->
        [{"additionalProperties:false", {:set, path ++ ["x-unknown-member"], {:integer, 1}}}]

      _open_or_absent ->
        []
    end
  end

  defp property_defects(document, schema, members, path) do
    subs = properties_of(schema)

    Enum.flat_map(members, fn {name, value} ->
      case List.keyfind(subs, name, 0) do
        {^name, sub} -> defects(document, sub, value, path ++ [name])
        nil -> []
      end
    end)
  end

  defp additional_defects(document, schema, members, path) do
    subs = properties_of(schema)

    case schema_member(schema, "additionalProperties") do
      {:object, _} = closure ->
        Enum.flat_map(members, fn {name, value} ->
          if List.keyfind(subs, name, 0) == nil,
            do: defects(document, closure, value, path ++ [name]),
            else: []
        end)

      _absent_or_boolean ->
        []
    end
  end

  defp scalar_defects(document, schema, path) do
    type_defect(schema, path) ++
      enum_defect(schema, path) ++
      const_defect(schema, path) ++
      minimum_defect(schema, path) ++
      maximum_defect(schema, path) ++
      min_length_defect(schema, path) ++
      max_length_defect(schema, path) ++
      min_items_defect(schema, path) ++
      max_items_defect(schema, path) ++
      one_of_defect(document, schema, path)
  end

  defp type_defect(schema, path) do
    case schema_member(schema, "type") do
      nil ->
        []

      type ->
        case wrong_typed_value(type_names(type)) do
          nil -> []
          value -> [{"type", {:set, path, value}}]
        end
    end
  end

  defp enum_defect(schema, path) do
    case schema_member(schema, "enum") do
      {:array, elements} ->
        case wrong_enum_value(elements) do
          nil -> []
          value -> [{"enum", {:set, path, value}}]
        end

      _absent ->
        []
    end
  end

  defp const_defect(schema, path) do
    case schema_member(schema, "const") do
      nil -> []
      value -> [{"const", {:set, path, wrong_const_value(value)}}]
    end
  end

  defp minimum_defect(schema, path) do
    case schema_member(schema, "minimum") do
      {:integer, bound} -> [{"minimum", {:set, path, {:integer, bound - 1}}}]
      _absent -> []
    end
  end

  defp maximum_defect(schema, path) do
    case schema_member(schema, "maximum") do
      {:integer, bound} -> [{"maximum", {:set, path, {:integer, bound + 1}}}]
      _absent -> []
    end
  end

  defp min_length_defect(schema, path) do
    case schema_member(schema, "minLength") do
      {:integer, bound} when bound > 0 ->
        [{"minLength", {:set, path, {:string, String.duplicate("x", bound - 1)}}}]

      _absent_or_zero ->
        []
    end
  end

  defp max_length_defect(schema, path) do
    case schema_member(schema, "maxLength") do
      {:integer, bound} ->
        [{"maxLength", {:set, path, {:string, String.duplicate("x", bound + 1)}}}]

      _absent ->
        []
    end
  end

  defp min_items_defect(schema, path) do
    case schema_member(schema, "minItems") do
      {:integer, bound} when bound > 0 ->
        [{"minItems", {:set, path, {:array, List.duplicate({:integer, 1}, bound - 1)}}}]

      _absent_or_zero ->
        []
    end
  end

  defp max_items_defect(schema, path) do
    case schema_member(schema, "maxItems") do
      {:integer, bound} ->
        [{"maxItems", {:set, path, {:array, List.duplicate({:integer, 1}, bound + 1)}}}]

      _absent ->
        []
    end
  end

  defp one_of_defect(document, schema, path) do
    case schema_member(schema, "oneOf") do
      {:array, branches} ->
        names =
          branches
          |> Enum.flat_map(fn branch ->
            case schema_member(resolve(document, branch), "type") do
              nil -> []
              type -> type_names(type)
            end
          end)
          |> MapSet.new()

        case wrong_typed_value(names) do
          nil -> []
          value -> [{"oneOf", {:set, path, value}}]
        end

      _absent ->
        []
    end
  end

  ## Defect application over the tagged algebra

  defp apply_defect(seed, {:set, [], value}), do: value
  defp apply_defect(seed, {:set, path, value}), do: set_at(seed, path, value)
  defp apply_defect(seed, {:delete, path}), do: delete_at(seed, path)

  defp set_at(_current, [], value), do: value

  defp set_at({:object, members}, [name | deeper], value) do
    case List.keyfind(members, name, 0) do
      {^name, existing} ->
        {:object, List.keystore(members, name, 0, {name, set_at(existing, deeper, value)})}

      nil when deeper == [] ->
        {:object, List.keystore(members, name, 0, {name, value})}

      nil ->
        raise "defect path traverses an absent member: #{name}"
    end
  end

  defp set_at({:array, items}, [index | deeper], value) do
    {:array, List.replace_at(items, index, set_at(Enum.at(items, index), deeper, value))}
  end

  defp delete_at({:object, members}, [name | deeper]),
    do: {:object, delete_member(members, name, deeper)}

  defp delete_at({:array, items}, [index | deeper]),
    do: {:array, delete_index(items, index, deeper)}

  defp delete_member(members, name, []), do: List.keydelete(members, name, 0)

  defp delete_member(members, name, deeper) do
    case List.keyfind(members, name, 0) do
      {^name, value} -> List.keystore(members, name, 0, {name, delete_at(value, deeper)})
      nil -> raise "defect path deletes an absent member: #{name}"
    end
  end

  defp delete_index(items, index, []), do: List.delete_at(items, index)

  defp delete_index(items, index, deeper) do
    List.replace_at(items, index, delete_at(Enum.at(items, index), deeper))
  end

  ## Tagged-schema navigation

  defp resolve(document, {:object, members}) do
    case List.keyfind(members, "$ref", 0) do
      {_, {:string, "#" <> pointer}} ->
        tokens =
          pointer
          |> String.split("/", trim: true)
          |> Enum.map(&unescape_token/1)

        navigate(document, tokens)

      _absent ->
        {:object, members}
    end
  end

  defp resolve(_document, node), do: node

  defp unescape_token(token) do
    token |> String.replace("~1", "/") |> String.replace("~0", "~")
  end

  defp navigate(node, []), do: node

  defp navigate({:object, members}, [token | rest]) do
    case List.keyfind(members, token, 0) do
      {^token, value} -> navigate(value, rest)
      nil -> raise "unresolvable schema pointer: #{token}"
    end
  end

  defp schema_member({:object, members}, key) do
    case List.keyfind(members, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp properties_of(schema) do
    case schema_member(schema, "properties") do
      {:object, subs} -> subs
      _absent -> []
    end
  end

  defp member_names({:array, names}), do: Enum.map(names, &elem(&1, 1))
  defp member_names(_absent), do: []

  defp type_names({:string, name}), do: [name]
  defp type_names({:array, names}), do: Enum.map(names, &elem(&1, 1))

  defp minimum_of(sub, default) do
    case schema_member(sub, "minimum") do
      {:integer, bound} -> bound
      _absent -> default
    end
  end

  defp unwrap_integer({:integer, value}), do: value
  defp unwrap_integer(_other), do: nil

  defp wrong_typed_value(allowed) do
    candidates = [
      {"integer", {:integer, 1}},
      {"string", {:string, "x"}},
      {"boolean", {:boolean, true}},
      {"array", {:array, []}},
      {"object", {:object, []}},
      {"null", :null}
    ]

    Enum.find_value(candidates, fn {name, value} ->
      if name not in allowed, do: value
    end)
  end

  defp wrong_enum_value(elements) do
    candidates = [{:string, "x-invalid-enum-member"}, {:integer, -1}, {:boolean, false}, :null]

    Enum.find_value(candidates, fn candidate ->
      if not Enum.any?(elements, &WireGrammar.equal?(&1, candidate)), do: candidate
    end)
  end

  defp wrong_const_value(const), do: wrong_enum_value([const])

  ## Verdict helpers

  defp assert_valid(schema, label, parsed, instance) do
    case WireGrammar.validate_instance(parsed, instance, WireGrammar.dialect()) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "wire schema positive failed: #{schema} #{label} (#{inspect(reason)})"
    end
  end

  defp assert_invalid(schema, label, parsed, instance) do
    case WireGrammar.validate_instance(parsed, instance, WireGrammar.dialect()) do
      {:error, _reason} -> :ok
      :ok -> raise "wire schema defect did not fail: #{schema} #{label}"
    end
  end

  ## Corpus file access

  defp corpus_files do
    @corpus_root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Map.new(fn path -> {Path.relative_to(path, @corpus_root), File.read!(path)} end)
  end

  defp corpus_file!(relative) do
    @corpus_root
    |> Path.join(relative)
    |> File.read!()
    |> decode!()
  end

  defp corpus_case_paths do
    @corpus_root
    |> Path.join("cases/*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, @corpus_root))
    |> Enum.sort()
  end

  defp case_of({:object, _members} = case_value), do: case_value

  defp valid_case?({:object, members}) do
    case List.keyfind(members, "class", 0) do
      {_, {:string, "valid"}} -> true
      _other -> false
    end
  end

  defp surface_of({:object, members}) do
    case List.keyfind(members, "surface", 0) do
      {_, {:string, surface}} -> surface
      _other -> nil
    end
  end

  defp input_of({:object, members}) do
    {_, input} = List.keyfind(members, "input", 0)
    input
  end

  defp case_compact(file, index) do
    case case_at(file, index) do
      {:object, members} ->
        {"input", {:object, input_members}} = List.keyfind(members, "input", 0)

        case List.keyfind(input_members, "compact", 0) do
          {"compact", {:string, compact}} -> compact
          _missing -> raise "case without compact: #{file} #{index}"
        end

      _other ->
        raise "case without compact: #{file} #{index}"
    end
  end

  defp case_revision_text(file, index) do
    {"input", {:object, members}} = List.keyfind(elem(case_at(file, index), 1), "input", 0)
    {"text", {:string, text}} = List.keyfind(members, "text", 0)
    decode!(text)
  end

  defp case_at(file, index) do
    @corpus_root
    |> Path.join("cases")
    |> Path.join(file)
    |> File.read!()
    |> decode!()
    |> then(fn {:object, members} ->
      {"cases", {:array, cases}} = List.keyfind(members, "cases", 0)
      Enum.at(cases, index)
    end)
  end

  defp compact_payload(compact) do
    [_protected, payload, _signature] = String.split(compact, ".")
    segment_value(payload)
  end

  defp compact_protected(compact) do
    [protected, _payload, _signature] = String.split(compact, ".")
    segment_value(protected)
  end

  defp segment_value(segment) do
    {:ok, bytes} = Base64Url.decode(segment)
    decode!(bytes)
  end

  defp member!({:object, members}, name) do
    {^name, value} = List.keyfind(members, name, 0)
    value
  end

  defp decode!(bytes) do
    case Json.decode(bytes) do
      {:ok, value} -> value
      {:error, reason} -> raise "wire json did not decode: #{inspect(reason)}"
    end
  end
end

case Cli.run(["--corpus", "priv/conformance"]) do
  0 ->
    CharterAgreementProtocol.ConformanceRegenerationGate.run()
    CharterAgreementProtocol.ConformanceMatrixGate.run()
    CharterAgreementProtocol.ConformanceSchemaGate.run()

    IO.puts(
      "conformance verification: certified index #{Report.index_identity(File.read!("priv/conformance/index.json"))}"
    )

  status ->
    Mix.raise("conformance verification exited #{status}")
end
