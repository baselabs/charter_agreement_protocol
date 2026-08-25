defmodule CharterAgreementProtocol.ArchitectureScan do
  @moduledoc false

  @source_roots ["lib", "test"]
  @path_roots ["lib", "priv", "test", "docs", "scripts", "verifier", "config"]
  @non_version_hump_stems ["Base", "Ed", "IPV", "IPv", "Ipv", "RFC", "Sha"]
  @package_source_identity {"mix.exs", :package_source_ref, ~S(source_ref: "v#{@version}")}
  @stance_terms [
    "non-authorizing",
    "never authorizes",
    "never authorises",
    "never grants authority",
    "does not authorize",
    "cannot authorize",
    "authorizes nothing",
    "no authority",
    "not a decision"
  ]

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

  def identifiers_from_source(source) when is_binary(source) do
    {_ast, identifiers} = source |> quoted() |> strip_docs() |> Macro.prewalk([], &collect/2)
    Enum.reverse(identifiers)
  end

  def authorization_token?(name) when is_binary(name),
    do: Regex.match?(~r/authoris|authoriz/i, name)

  def term_evaluation_token?(name) when is_binary(name),
    do: Regex.match?(~r/(^|_)(compliant|within_limit|permitted|satisfied|in_band)($|_)/i, name)

  def string_literals(paths) when is_list(paths) do
    paths
    |> Enum.flat_map(fn path ->
      {_ast, strings} = Macro.prewalk(quoted(path), [], &collect_string/2)
      strings
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def production_beams do
    :charter_agreement_protocol
    |> Application.app_dir("ebin/*.beam")
    |> Path.wildcard()
    |> Enum.sort()
  end

  def beam_remote_calls(beam_path) do
    disassembly = :beam_disasm.file(String.to_charlist(to_string(beam_path)))
    self_module = elem(disassembly, 1)

    disassembly
    |> elem(5)
    |> collect_remote(self_module, [])
    |> Enum.uniq()
  end

  def public_contract_findings do
    ["lib"]
    |> source_files()
    |> Enum.flat_map(fn path ->
      path
      |> File.read!()
      |> source_contract_findings()
      |> Enum.map(&{path, &1})
    end)
  end

  def source_contract_findings(source) when is_binary(source) do
    source
    |> quoted()
    |> module_tree()
    |> Enum.flat_map(fn {module, info} ->
      missing_specs =
        for {name, arity} <- info.publics,
            {name, arity} not in info.specs,
            do: {:missing_spec, module, name, arity}

      if missing_stance?(info.doc),
        do: [{:missing_stance, module} | missing_specs],
        else: missing_specs
    end)
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
          :ReceiptFacts,
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

  defp collect_string(value, acc) when is_binary(value), do: {value, [value | acc]}
  defp collect_string(node, acc), do: {node, acc}

  defp collect_remote({:extfunc, module, function, _arity}, _self, acc)
       when is_atom(module) and is_atom(function),
       do: [{module, function} | acc]

  defp collect_remote({:apply, _arity}, _self, acc), do: [{:erlang, :apply} | acc]

  defp collect_remote({:apply_last, _arity, _deallocate}, _self, acc),
    do: [{:erlang, :apply} | acc]

  defp collect_remote({:call, _arity, {module, function, _call_arity}} = instruction, self, acc)
       when is_atom(module) and is_atom(function) do
    if module == self,
      do: acc,
      else: collect_remote(instruction |> Tuple.to_list(), self, [{module, function} | acc])
  end

  defp collect_remote(tuple, self, acc) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.reduce(acc, &collect_remote(&1, self, &2))

  defp collect_remote([head | tail], self, acc),
    do: collect_remote(tail, self, collect_remote(head, self, acc))

  defp collect_remote(_node, _self, acc), do: acc

  defp module_tree({:__block__, _, statements}),
    do: Enum.flat_map(statements, &walk_module(&1, nil))

  defp module_tree(ast), do: walk_module(ast, nil)

  defp walk_module({:defmodule, _, [{:__aliases__, _, segments}, [do: body]]}, parent) do
    module = join_module(parent, segments)
    statements = block_statements(body)

    [
      {module,
       %{
         doc: direct_moduledoc(statements),
         specs: direct_specs(statements),
         publics: direct_publics(statements)
       }}
      | Enum.flat_map(statements, &walk_child(&1, module))
    ]
  end

  defp walk_module(_node, _parent), do: []

  defp walk_child({:defmodule, _, [{:__aliases__, _, _}, _]} = node, parent),
    do: walk_module(node, parent)

  defp walk_child({:__block__, _, statements}, parent),
    do: Enum.flat_map(statements, &walk_child(&1, parent))

  defp walk_child(_node, _parent), do: []

  defp join_module(nil, segments), do: Module.concat(segments)
  defp join_module(parent, segments), do: Module.concat([parent | segments])

  defp direct_specs(statements) do
    for {:@, _, [{:spec, _, [raw]}]} <- statements,
        spec = unwrap_when(raw),
        {:"::", _, [{name, _, arguments}, _return]} <- [spec],
        is_atom(name),
        do: {name, if(is_list(arguments), do: length(arguments), else: 0)}
  end

  defp unwrap_when({:when, _, [inner, _guards]}), do: inner
  defp unwrap_when(other), do: other

  defp direct_publics(statements) do
    for {kind, _, [head, _body]} <- statements,
        kind in [:def, :defmacro, :defdelegate],
        {name, arity} <- [head_arity(head)] |> Enum.reject(&is_nil/1),
        do: {name, arity}
  end

  defp head_arity({:when, _, [head, _guards]}), do: head_arity(head)

  defp head_arity({name, _, arguments}) when is_atom(name) and is_list(arguments),
    do: {name, length(arguments)}

  defp head_arity({name, _, _arguments}) when is_atom(name), do: {name, 0}
  defp head_arity(_head), do: nil

  defp direct_moduledoc(statements) do
    Enum.find_value(statements, fn
      {:@, _, [{:moduledoc, _, [doc]}]} -> doc
      _statement -> nil
    end)
  end

  defp block_statements({:__block__, _, statements}), do: statements
  defp block_statements([{:do, body} | _rest]), do: block_statements(body)
  defp block_statements(other) when is_list(other), do: other
  defp block_statements(other), do: [other]

  defp missing_stance?(doc) do
    case doc_text(doc) do
      text when is_binary(text) ->
        downcased = String.downcase(text)
        not Enum.any?(@stance_terms, &String.contains?(downcased, &1))

      _missing_or_non_string ->
        true
    end
  end

  defp doc_text(doc) when is_binary(doc), do: doc

  defp doc_text({:<<>>, _, segments}) when is_list(segments) do
    Enum.map_join(segments, "", fn
      segment when is_binary(segment) -> segment
      _interpolation -> ""
    end)
  end

  defp doc_text(_doc), do: nil

  defp quoted(input) do
    source = if File.regular?(input), do: File.read!(input), else: input
    Code.string_to_quoted!(source, file: input)
  end

  defp maybe_unsafe_detail(detail, acc)
       when is_nil(detail) or is_atom(detail) or is_binary(detail),
       do: acc

  defp maybe_unsafe_detail(detail, acc), do: [detail | acc]
end
