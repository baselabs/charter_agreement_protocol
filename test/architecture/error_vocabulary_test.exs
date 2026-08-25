defmodule CharterAgreementProtocol.Architecture.ErrorVocabularyTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{ArchitectureScan, Error}

  test "every production error construction uses a declared literal code" do
    calls =
      Enum.flat_map(ArchitectureScan.source_files(["lib"]), &ArchitectureScan.error_code_calls/1)

    dynamic = Enum.reject(calls, &is_atom/1)
    undeclared = for code <- calls, is_atom(code), not Error.declared?(code), do: code

    assert dynamic == []
    assert undeclared == []
  end

  test "every declared code has a production emission site" do
    emitted =
      ArchitectureScan.source_files(["lib"])
      |> Enum.flat_map(&ArchitectureScan.error_code_calls/1)
      |> Enum.filter(&is_atom/1)
      |> Enum.uniq()
      |> Enum.sort()

    assert emitted == Enum.sort(Error.codes())
  end

  test "renaming or importing the error constructor cannot bypass the vocabulary scan" do
    assert ArchitectureScan.error_constructor_bypass_findings(
             "alias CharterAgreementProtocol.Error, as: E\nE.new(:invented)"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "import CharterAgreementProtocol.Error\nnew(:invented)"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "require CharterAgreementProtocol.Error, as: E\nE.new(:invented)"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "alias Elixir.CharterAgreementProtocol.Error, as: E\nE.new(:invented)"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "%CharterAgreementProtocol.Error{code: :invented, subject: []}"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "struct(CharterAgreementProtocol.Error, code: :invented, subject: [])"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "apply(CharterAgreementProtocol.Error, :new, [:invented, [], rejected])"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "&CharterAgreementProtocol.Error.new/3"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "Kernel.apply(Error, :new, [:invented, [], rejected])"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             ":erlang.apply(Error, :new, [:invented, [], rejected])"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "Kernel.struct(Error, code: :invented, subject: [])"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "%Error{code: :invented, subject: []}"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings("%Error{} = error") == []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "%CharterAgreementProtocol.Error{code: code} = error"
           ) == []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "Function.capture(CharterAgreementProtocol.Error, :new, 3)"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "Elixir.Function.capture(CharterAgreementProtocol.Error, :new, 3)"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "Elixir.Kernel.apply(Error, :new, [:invented, [], rejected])"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "Elixir.Kernel.struct(Error, code: :invented, subject: [])"
           ) != []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "alias CharterAgreementProtocol.Error\nError.new(:invalid_type)"
           ) == []

    assert Enum.flat_map(
             ArchitectureScan.source_files(["lib"]),
             &ArchitectureScan.error_constructor_bypass_findings/1
           ) == []
  end

  test "production error details are protocol-owned literals" do
    assert ArchitectureScan.unsafe_error_detail_findings(
             ~S|Error.new(:invalid_type, [], rejected_input)|
           ) != []

    assert ArchitectureScan.unsafe_error_detail_findings(
             ~S|Error.new(:invalid_type, [], "protocol-detail")|
           ) == []

    assert ArchitectureScan.unsafe_error_detail_findings(
             ~S|Elixir.CharterAgreementProtocol.Error.new(:invalid_type, [], rejected_input)|
           ) != []

    assert Enum.flat_map(
             ArchitectureScan.source_files(["lib"]),
             &ArchitectureScan.unsafe_error_detail_findings/1
           ) == []
  end

  test "Elixir-prefixed direct calls remain visible to the code-vocabulary census" do
    assert ArchitectureScan.error_code_calls(
             ~S|Elixir.CharterAgreementProtocol.Error.new(:invalid_type)|
           ) == [:invalid_type]
  end

  test "read-only Error patterns are not classified as construction" do
    assert ArchitectureScan.error_constructor_bypass_findings(
             "case error do %Error{code: code} -> code end"
           ) == []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "def code(%Error{code: code}), do: code"
           ) == []

    assert ArchitectureScan.error_constructor_bypass_findings(
             "with %Error{code: code} <- error, do: code"
           ) == []
  end
end
