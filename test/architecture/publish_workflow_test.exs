defmodule PublishWorkflowTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "publication only uploads verified archives without loading project code under the key" do
    workflow = File.read!(Path.join(@root, ".github/workflows/publish.yml"))
    refute workflow =~ "hex.publish"
    refute workflow =~ "push:"
    refute workflow =~ "tags:"
    assert workflow =~ "workflow_dispatch:"
    assert workflow =~ "timeout-minutes: 90 # no green run yet"
    assert workflow =~ "install-hex: false"
    assert workflow =~ "mix local.hex 2.7.0 --force"
    assert workflow =~ "mix docs --warnings-as-errors --formatter html"

    steps = String.split(workflow, ~r/^      - /m) |> tl()
    keyed_steps = Enum.filter(steps, &String.contains?(&1, "HEX_API_KEY"))
    assert [keyed] = keyed_steps
    assert keyed =~ "HEX_API_KEY: ${{ secrets.HEX_API_KEY }}"

    assert length(Regex.scan(~r/HEX_API_KEY/, workflow)) ==
             length(Regex.scan(~r/HEX_API_KEY/, keyed))

    assert keyed =~ "working-directory: release-assets"
    assert keyed =~ "mix run --no-mix-exs ../scripts/hex_upload.exs"
    refute keyed =~ "mix hex.build"
    refute keyed =~ "mix docs"

    assert [artifact] = Enum.filter(steps, &String.contains?(&1, "actions/upload-artifact@"))
    assert artifact =~ "name: release-assets\n"
    assert artifact =~ "path: release-assets/*"
    assert artifact =~ "if-no-files-found: error"
    assert workflow =~ "id: plan"
    assert workflow =~ "hex_release_state.exs\" --plan"
    assert workflow =~ "hex_release_state.exs\" --served"

    # The docs path is a read-back destination, never an archive to compare.
    assert [plan, served] = Enum.filter(steps, &String.contains?(&1, "hex_release_state.exs"))
    assert plan =~ "--plan"
    refute plan =~ "-docs.tar.gz"
    refute plan =~ "--commit"
    refute plan =~ "--clone"
    refute plan =~ "--docs-output"
    assert served =~ "id: served"
    assert served =~ ~s(--commit "$GITHUB_SHA" --clone "$GITHUB_WORKSPACE")
    assert served =~ ~r/--docs-output "\$GITHUB_WORKSPACE\/release-assets\/[^" ]+-docs\.tar\.gz"/
    assert length(Regex.scan(~r/-docs\.tar\.gz/, served)) == 1

    assert [provenance] = Enum.filter(steps, &String.contains?(&1, "doc/release.json"))
    assert provenance =~ "JSON.encode!"
    assert provenance =~ ~s|"package" => System.fetch_env!("DOCS_PACKAGE")|
    assert provenance =~ ~s|"version" => System.fetch_env!("VERSION")|
    assert provenance =~ ~s|"commit" => System.fetch_env!("GITHUB_SHA")|

    {docs_position, _} = :binary.match(workflow, "mix docs --warnings-as-errors")
    {provenance_position, _} = :binary.match(workflow, "doc/release.json")
    {archive_position, _} = :binary.match(workflow, "tar --sort=name")
    {served_position, _} = :binary.match(workflow, "id: served")
    {checksum_position, _} = :binary.match(workflow, "name: Record release checksums")
    {artifact_position, _} = :binary.match(workflow, "actions/upload-artifact@")
    assert docs_position < provenance_position
    assert provenance_position < archive_position
    assert served_position < checksum_position
    assert checksum_position < artifact_position
    assert String.trim(List.last(steps)) =~ "if: always()"
    assert List.last(steps) =~ "name: Remove release archives"
  end
end
