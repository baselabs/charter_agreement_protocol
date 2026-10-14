defmodule CharterAgreementProtocol.StrictEd25519FixtureTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Signature}

  @root Path.expand("../fixtures/strict-ed25519", __DIR__)

  test "the copied files match the recorded hashes and case counts" do
    manifest = manifest()
    assert manifest["total_cases"] == 1300
    assert length(manifest["files"]) == 12

    paths = Path.wildcard(Path.join(@root, "cases/**/*.json"))

    assert Enum.sort(Enum.map(paths, &Path.relative_to(&1, @root))) ==
             Enum.sort(Enum.map(manifest["files"], & &1["path"]))

    for entry <- manifest["files"] do
      bytes = File.read!(Path.join(@root, entry["path"]))
      hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      assert hash == entry["sha256"], entry["path"]
      assert length(:json.decode(bytes)["cases"]) == entry["cases"], entry["path"]
    end

    refute Enum.any?(Mix.Project.config()[:package][:files], &String.starts_with?(&1, "test"))
  end

  test "every strict primitive case matches its expected verdict" do
    cases =
      Enum.flat_map(manifest()["files"], fn entry ->
        @root |> Path.join(entry["path"]) |> File.read!() |> :json.decode() |> Map.fetch!("cases")
      end)

    assert length(cases) == 1300
    assert MapSet.size(MapSet.new(cases, & &1["id"])) == 1300

    assert Enum.frequencies_by(cases, & &1["surface"]) == %{
             "ed25519.verify_strict" => 1221,
             "ed25519.acceptable_public_key" => 79
           }

    verdicts =
      for one <- cases do
        input = one["input"]
        public = decode(input["public_key"])

        actual =
          case one["surface"] do
            "ed25519.verify_strict" ->
              case Signature.verify(
                     decode(input["message"]),
                     decode(input["signature"]),
                     public,
                     "Ed25519"
                   ) do
                :ok -> "valid"
                {:error, %Error{code: :signature_invalid}} -> "invalid"
              end

            "ed25519.acceptable_public_key" ->
              if Signature.valid_key?(public, "Ed25519"), do: "valid", else: "invalid"
          end

        {one["id"], one["expected"]["verdict"], actual}
      end

    mismatches = Enum.filter(verdicts, fn {_id, expected, actual} -> expected != actual end)
    assert mismatches == [], "#{length(mismatches)} primitive verdicts differ"
  end

  defp manifest, do: @root |> Path.join("hashes.json") |> File.read!() |> :json.decode()
  defp decode(value), do: Base.url_decode64!(value, padding: false)
end
