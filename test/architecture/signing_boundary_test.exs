defmodule CharterAgreementProtocol.Architecture.SigningBoundaryTest do
  use ExUnit.Case, async: true

  @forbidden_source [
    ~r/:crypto\.sign\s*\(/,
    ~r/\bapply\s*\(\s*:crypto\s*,\s*:sign\b/,
    ~r/&\s*:crypto\.sign(?:\s*\/|\s*\()/,
    ~r/\bprivate_key\b/,
    ~r/\bsigning_callback\b/,
    ~r/\bsigner_module\b/,
    ~r/\bkey_handle\b/
  ]

  test "production source and compiled modules contain verification but no signing custody" do
    source_offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        source = File.read!(path)

        for pattern <- @forbidden_source,
            Regex.match?(pattern, source),
            do: {path, Regex.source(pattern)}
      end)

    beam_offenders =
      :charter_agreement_protocol
      |> Application.spec(:modules)
      |> Enum.filter(&production_module?/1)
      |> Enum.flat_map(&forbidden_beam_calls/1)

    assert source_offenders == []
    assert beam_offenders == []
  end

  test "the frozen facade exposes only external-signature assembly" do
    exports = CharterAgreementProtocol.module_info(:exports)

    for expected <- [
          descriptor_signing_input: 1,
          receipt_signing_input: 1,
          acceptance_signing_input: 2,
          termination_signing_input: 2,
          assemble_compact: 2
        ] do
      assert expected in exports
    end

    refute Enum.any?(exports, fn {name, _arity} ->
             Regex.match?(~r/\Asign(?:_|\z)/, Atom.to_string(name))
           end)
  end

  defp production_module?(module) do
    source = module.module_info(:compile)[:source] |> List.to_string()
    String.starts_with?(source, Path.expand("lib/"))
  end

  defp forbidden_beam_calls(module) do
    beam =
      Application.app_dir(
        :charter_agreement_protocol,
        Path.join("ebin", Atom.to_string(module) <> ".beam")
      )

    case :beam_lib.chunks(String.to_charlist(beam), [:abstract_code]) do
      {:ok, {_module, [abstract_code: {_format, forms}]}} when is_list(forms) ->
        forms
        |> collect_forbidden([])
        |> Enum.map(&{module, &1})

      unavailable ->
        [{module, {:beam_unavailable, unavailable}}]
    end
  end

  defp collect_forbidden(
         {:call, _line, {:atom, _apply_line, :apply},
          [{:atom, _module_line, :crypto}, {:atom, _function_line, :sign}, _arguments]} = node,
         calls
       ) do
    descend(node, [{:crypto, :sign} | calls])
  end

  defp collect_forbidden(
         {:call, _line,
          {:remote, _remote_line, {:atom, _erlang_line, :erlang}, {:atom, _apply_line, :apply}},
          [{:atom, _module_line, :crypto}, {:atom, _function_line, :sign}, _arguments]} = node,
         calls
       ) do
    descend(node, [{:crypto, :sign} | calls])
  end

  defp collect_forbidden(
         {:remote, _line, {:atom, _module_line, :crypto}, {:atom, _function_line, :sign}} = node,
         calls
       ) do
    descend(node, [{:crypto, :sign} | calls])
  end

  defp collect_forbidden(tuple, calls) when is_tuple(tuple), do: descend(tuple, calls)

  defp collect_forbidden(list, calls) when is_list(list),
    do: Enum.reduce(list, calls, &collect_forbidden/2)

  defp collect_forbidden(_leaf, calls), do: calls

  defp descend(tuple, calls) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(calls, &collect_forbidden/2)
  end
end
