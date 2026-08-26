defmodule CharterAgreementProtocol.Architecture.NormativeSpecTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.RequirementMap

  @core_path "spec/core.md"
  @keyword_pattern ~r/\b(?:MUST NOT|SHALL NOT|SHOULD NOT|NOT RECOMMENDED|MUST|SHALL|SHOULD|RECOMMENDED|REQUIRED|MAY|OPTIONAL)\b/

  test "every uppercase normative keyword statement carries a bound requirement ID" do
    assert {:ok, contents} = File.read(@core_path)

    # A normative statement is a paragraph; its requirement ID closes it.
    unbound =
      for paragraph <- String.split(contents, "\n\n"),
          # The RFC 8174 boilerplate paragraph quotes the keywords themselves.
          not String.contains?(paragraph, "BCP 14"),
          Regex.match?(@keyword_pattern, paragraph),
          not Regex.match?(~r/CAP-[A-Z0-9-]+-[a-z0-9]+(?:-[a-z0-9]+)*/, paragraph) do
        String.split(paragraph, "\n") |> hd() |> String.trim()
      end

    assert unbound == []
  end

  test "every requirement ID cited in the core spec is bound in the matrix" do
    assert {:ok, contents} = File.read(@core_path)
    bound = RequirementMap.entries() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    cited =
      ~r/CAP-[A-Z0-9-]+-[a-z0-9]+(?:-[a-z0-9]+)*/
      |> Regex.scan(contents, capture: :first)
      |> List.flatten()
      |> MapSet.new()

    unknown = MapSet.difference(cited, bound)
    assert MapSet.size(unknown) == 0
  end

  test "every bound requirement is stated in the core spec" do
    assert {:ok, contents} = File.read(@core_path)

    stated =
      ~r/CAP-[A-Z0-9-]+-[a-z0-9]+(?:-[a-z0-9]+)*/
      |> Regex.scan(contents, capture: :first)
      |> List.flatten()
      |> MapSet.new()

    bound = RequirementMap.entries() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    unstated = MapSet.difference(bound, stated)
    assert MapSet.size(unstated) == 0
  end
end
