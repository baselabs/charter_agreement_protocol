defmodule CharterAgreementProtocol.ArchitectureScan do
  @moduledoc false

  @source_roots ["lib", "test"]
  @path_roots ["lib", "priv", "test", "docs", "scripts", "verifier", "config"]
  @non_version_hump_stems ["Base", "Ed", "IPV", "IPv", "Ipv", "RFC", "Sha"]
  @package_source_identity {"mix.exs", :package_source_ref, ~S(source_ref: "v#{@version}")}

  def source_files(roots \\ @source_roots) do
    roots
    |> Enum.flat_map(fn root -> Path.wildcard(Path.join(root, "**/*.{ex,exs}")) end)
    |> Enum.sort()
  end

  def owned_paths do
    root_paths =
      @path_roots
      |> Enum.flat_map(fn root -> Path.wildcard(Path.join(root, "**/*"), match_dot: true) end)
      |> Enum.reject(&File.dir?/1)

    root_files =
      ["mix.exs", "mix.lock", ".formatter.exs", ".credo.exs"]
      |> Enum.filter(&File.exists?/1)

    (root_paths ++ root_files) |> Enum.uniq() |> Enum.sort()
  end

  def path_segments do
    owned_paths()
    |> Enum.flat_map(&Path.split/1)
    |> Enum.map(&Path.rootname/1)
    |> Enum.uniq()
  end

  def identifiers(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path)
    {_ast, identifiers} = ast |> strip_docs() |> Macro.prewalk([], &collect/2)
    Enum.reverse(identifiers)
  end

  def module_references(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:__aliases__, _, segments} = node, acc when is_list(segments) ->
          {node, [Enum.map_join(segments, ".", &Atom.to_string/1) | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(references)
  end

  def package_source_ref_observations do
    "mix.exs"
    |> File.read!()
    |> then(&Regex.scan(~r/source_ref:\s*"v(?:#\{@version\}|\d+)"/, &1))
    |> Enum.map(fn [name] -> %{path: "mix.exs", kind: :package_source_ref, name: name} end)
  end

  def version_token?(string) when is_binary(string) do
    Regex.match?(~r/(^|_)v\d/i, string) or
      Regex.match?(~r/[a-z0-9]V\d/, string) or
      version_hump_digit?(string)
  end

  def check_durable_identifier(%{path: path, kind: kind, name: name}) do
    if {path, kind, name} == @package_source_identity do
      :ok
    else
      if version_token?(name) or package_source_ref?(name),
        do: {:error, :implementation_version_identifier},
        else: :ok
    end
  end

  def error_code_calls(path) do
    ast = quoted(path)

    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, segments}, :new]}, _, [code | _]} = node, acc ->
          if error_alias?(segments), do: {node, [code | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(calls)
  end

  def error_constructor_bypass_findings(input) do
    ast = input |> quoted() |> strip_read_patterns()

    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, acc ->
        case error_constructor_bypass(node) do
          nil -> {node, acc}
          finding -> {node, [finding | acc]}
        end
      end)

    Enum.reverse(findings)
  end

  def unsafe_error_detail_findings(input) do
    ast = quoted(input)

    {_ast, findings} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, segments}, :new]}, _, [_code, _subject, detail]} = node,
        acc ->
          if error_alias?(segments),
            do: {node, maybe_unsafe_detail(detail, acc)},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(findings)
  end

  def facts_constructor_bypass_findings(input) do
    ast = input |> quoted() |> strip_fact_read_patterns()

    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, acc ->
        case facts_constructor_bypass(node) do
          nil -> {node, acc}
          finding -> {node, [finding | acc]}
        end
      end)

    Enum.reverse(findings)
  end

  defp package_source_ref?(name),
    do: Regex.match?(~r/\bsource_ref\b.*\bv(?:#\{@version\}|\d)/i, name)

  defp version_hump_digit?(string) do
    ~r/[A-Z]+[a-z]*\d+/
    |> Regex.scan(string)
    |> Enum.map(fn [word] -> Regex.replace(~r/\d+\z/, word, "") end)
    |> Enum.any?(&(&1 not in @non_version_hump_stems))
  end

  defp error_alias?(segments),
    do: normalize_elixir_prefix(segments) in [[:Error], [:CharterAgreementProtocol, :Error]]

  defp error_constructor_bypass({directive, _, [{:__aliases__, _, segments}, options]})
       when directive in [:alias, :require] and is_list(segments) and is_list(options) do
    if error_alias?(segments), do: renamed_constructor(Keyword.get(options, :as))
  end

  defp error_constructor_bypass({:import, _, [{:__aliases__, _, segments} | _]}) do
    if error_alias?(segments), do: :imported_error_constructor
  end

  defp error_constructor_bypass({:%, _, [{:__aliases__, _, segments}, {:%{}, _, fields}]}) do
    if error_alias?(segments) and fields != [], do: :literal_error_struct
  end

  defp error_constructor_bypass({constructor, _, [{:__aliases__, _, segments} | _arguments]})
       when constructor in [:struct, :struct!] do
    if error_alias?(segments), do: :dynamic_error_struct
  end

  defp error_constructor_bypass({:apply, _, [{:__aliases__, _, segments}, :new, _arguments]}) do
    if error_alias?(segments), do: :applied_error_constructor
  end

  defp error_constructor_bypass(
         {{:., _, [{:__aliases__, _, caller}, :apply]}, _,
          [{:__aliases__, _, segments}, :new, _arguments]}
       ) do
    if normalize_elixir_prefix(caller) in [[:Kernel], [:erlang]] and error_alias?(segments),
      do: :applied_error_constructor
  end

  defp error_constructor_bypass(
         {{:., _, [:erlang, :apply]}, _, [{:__aliases__, _, segments}, :new, _arguments]}
       ) do
    if error_alias?(segments), do: :applied_error_constructor
  end

  defp error_constructor_bypass(
         {{:., _, [{:__aliases__, _, caller}, constructor]}, _,
          [{:__aliases__, _, segments} | _arguments]}
       )
       when constructor in [:struct, :struct!] do
    if normalize_elixir_prefix(caller) == [:Kernel] and error_alias?(segments),
      do: :dynamic_error_struct
  end

  defp error_constructor_bypass(
         {:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, segments}, :new]}, _, []}, _arity]}]}
       ) do
    if error_alias?(segments), do: :captured_error_constructor
  end

  defp error_constructor_bypass(
         {{:., _, [{:__aliases__, _, caller}, :capture]}, _,
          [{:__aliases__, _, segments}, :new, _arity]}
       ) do
    if normalize_elixir_prefix(caller) == [:Function] and error_alias?(segments),
      do: :captured_error_constructor
  end

  defp error_constructor_bypass(_node), do: nil

  defp facts_constructor_bypass({:alias, _, [{:__aliases__, _, segments}, options]})
       when is_list(options) do
    if fact_module?(segments) and Keyword.has_key?(options, :as),
      do: :renamed_facts_module
  end

  defp facts_constructor_bypass({:@, _, [{_name, _, [{:__aliases__, _, segments}]}]}) do
    if fact_module?(segments), do: :facts_module_indirection
  end

  defp facts_constructor_bypass({:%, _, [{:__aliases__, _, segments}, {:%{}, _, _fields}]}) do
    if fact_module?(segments), do: :literal_facts_struct
  end

  defp facts_constructor_bypass({constructor, _, [{:__aliases__, _, segments} | _arguments]})
       when constructor in [:struct, :struct!] do
    if fact_module?(segments), do: :dynamic_facts_struct
  end

  defp facts_constructor_bypass(
         {{:., _, [{:__aliases__, _, caller}, constructor]}, _,
          [{:__aliases__, _, segments} | _arguments]}
       )
       when constructor in [:struct, :struct!] do
    if normalize_elixir_prefix(caller) == [:Kernel] and fact_module?(segments),
      do: :dynamic_facts_struct
  end

  defp facts_constructor_bypass(
         {:apply, _, [{:__aliases__, _, segments}, :__struct__, _arguments]}
       ) do
    if fact_module?(segments), do: :applied_facts_constructor
  end

  defp facts_constructor_bypass(_node), do: nil

  defp renamed_constructor(nil), do: nil
  defp renamed_constructor({:__aliases__, _, [:Error]}), do: nil
  defp renamed_constructor(renamed), do: {:renamed_error_constructor, renamed}

  defp normalize_elixir_prefix([Elixir | rest]), do: rest
  defp normalize_elixir_prefix(segments), do: segments

  defp fact_module?(segments) do
    segments
    |> normalize_elixir_prefix()
    |> List.last()
    |> then(
      &(&1 in [
          :AcceptanceFacts,
          :ChainFacts,
          :DescriptorFacts,
          :ForkEvidence,
          :RevisionFacts,
          :TerminationFacts
        ])
    )
  end

  defp strip_read_patterns(ast) do
    Macro.prewalk(ast, fn
      {:=, meta, [left, right]} ->
        {:=, meta, [strip_error_fields(left), right]}

      {:<-, meta, [left, right]} ->
        {:<-, meta, [strip_error_fields(left), right]}

      {:->, meta, [patterns, body]} ->
        {:->, meta, [strip_clause_patterns(patterns), body]}

      {kind, meta, [head, body]} when kind in [:def, :defp, :defmacro, :defmacrop] ->
        {kind, meta, [strip_function_head(head), body]}

      node ->
        node
    end)
  end

  defp strip_fact_read_patterns(ast) do
    Macro.prewalk(ast, fn
      {:match?, meta, [pattern, value]} ->
        {:match?, meta, [strip_fact_fields(pattern), value]}

      {:=, meta, [left, right]} ->
        {:=, meta, [strip_fact_fields(left), right]}

      {:<-, meta, [left, right]} ->
        {:<-, meta, [strip_fact_fields(left), right]}

      {:->, meta, [patterns, body]} ->
        {:->, meta, [Enum.map(patterns, &strip_fact_fields/1), body]}

      {kind, meta, [head, body]} when kind in [:def, :defp, :defmacro, :defmacrop] ->
        {kind, meta, [strip_fact_function_head(head), body]}

      node ->
        node
    end)
  end

  defp strip_fact_function_head({:when, meta, [head | guards]}) do
    {:when, meta, [strip_fact_function_head(head) | guards]}
  end

  defp strip_fact_function_head({name, meta, arguments})
       when is_atom(name) and is_list(arguments) do
    {name, meta, Enum.map(arguments, &strip_fact_argument/1)}
  end

  defp strip_fact_function_head(head), do: head

  defp strip_fact_argument({:\\, meta, [pattern, default]}) do
    {:\\, meta, [strip_fact_fields(pattern), default]}
  end

  defp strip_fact_argument(pattern), do: strip_fact_fields(pattern)

  defp strip_fact_fields(ast) do
    Macro.prewalk(ast, fn
      {:%, _, [{:__aliases__, _, segments}, {:%{}, _, _fields}]} = node ->
        if fact_module?(segments), do: :fact_pattern, else: node

      node ->
        node
    end)
  end

  defp strip_clause_patterns(patterns), do: Enum.map(patterns, &strip_error_fields/1)

  defp strip_function_head({:when, meta, [head | guards]}) do
    {:when, meta, [strip_function_head(head) | guards]}
  end

  defp strip_function_head({name, meta, arguments}) when is_atom(name) and is_list(arguments) do
    {name, meta, Enum.map(arguments, &strip_function_argument/1)}
  end

  defp strip_function_head(head), do: head

  defp strip_function_argument({:\\, meta, [pattern, default]}) do
    {:\\, meta, [strip_error_fields(pattern), default]}
  end

  defp strip_function_argument(pattern), do: strip_error_fields(pattern)

  defp strip_error_fields(ast) do
    Macro.prewalk(ast, fn
      {:%, meta, [{:__aliases__, _, segments} = name, {:%{}, fields_meta, _fields}]} = node ->
        if error_alias?(segments), do: {:%, meta, [name, {:%{}, fields_meta, []}]}, else: node

      node ->
        node
    end)
  end

  defp strip_docs(ast) do
    Macro.prewalk(ast, fn
      {:@, _, [{doc, _, [_body]}]} when doc in [:moduledoc, :doc, :typedoc, :shortdoc] ->
        {:@, [], [{doc, [], [true]}]}

      other ->
        other
    end)
  end

  defp collect({:defmodule, _, [{:__aliases__, _, segments} | _]} = node, acc) do
    names = Enum.map(segments, &{:module, Atom.to_string(&1)})
    {node, Enum.reverse(names) ++ acc}
  end

  defp collect({kind, _, [{name, _, _} | _]} = node, acc)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_atom(name),
       do: {node, [{:function, Atom.to_string(name)} | acc]}

  defp collect({kind, _, [name | _]} = node, acc)
       when kind in [:test, :describe] and is_binary(name),
       do: {node, [{:test_name, name} | acc]}

  defp collect(atom, acc) when is_atom(atom) and atom not in [nil, true, false],
    do: {atom, [{:atom, Atom.to_string(atom)} | acc]}

  defp collect(node, acc), do: {node, acc}

  defp quoted(input) do
    source = if File.regular?(input), do: File.read!(input), else: input
    Code.string_to_quoted!(source, file: input)
  end

  defp maybe_unsafe_detail(detail, acc)
       when is_nil(detail) or is_atom(detail) or is_binary(detail),
       do: acc

  defp maybe_unsafe_detail(detail, acc), do: [detail | acc]
end
