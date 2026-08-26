defmodule CharterAgreementProtocol.Architecture.PackageBoundaryTest do
  use ExUnit.Case, async: true

  @index_sha "SiGK6zgrI9Rv5BvBPgj3-EexxJ1udz8-XtDDjeOiRv0"

  test "the explicit package boundary includes certified release evidence and excludes tooling" do
    files = CharterAgreementProtocol.MixProject.project()[:package][:files]

    assert "priv/release-metadata.json" in files
    assert "spec" in files
    assert "docs/errata.md" in files
    assert "docs/adr/conformance-release-candidate.md" in files
    refute Enum.any?(files, &String.starts_with?(&1, "verifier"))
    refute Enum.any?(files, &String.starts_with?(&1, "scripts"))
    refute Enum.any?(files, &String.starts_with?(&1, "test"))
  end

  test "release metadata pins the certified corpus and records no publication authority" do
    metadata = :json.decode(File.read!("priv/release-metadata.json"))
    index = :json.decode(File.read!("priv/conformance/index.json"))

    assert metadata["package"] == "charter_agreement_protocol"
    assert metadata["package_version"] == Mix.Project.config()[:version]
    assert metadata["corpus_digest"] == index["corpus_digest"]
    assert metadata["registry_digest"] == index["registry_digest"]
    assert metadata["index_sha256_base64url"] == @index_sha
    assert metadata["archive_is_publication_authorization"] == false
  end

  test "release metadata pins the live specification digest" do
    metadata = :json.decode(File.read!("priv/release-metadata.json"))

    live =
      "spec/**/*"
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&{Path.relative_to(&1, "spec"), File.read!(&1)})
      |> CharterAgreementProtocol.SpecificationIdentity.digest()
      |> CharterAgreementProtocol.Digest.to_tagged()

    assert metadata["spec_digest"] == live
  end

  test "no alias or project callback can publish the package" do
    project_source = File.read!("mix.exs")
    refute project_source =~ "hex.publish"
    refute Map.has_key?(Map.new(Mix.Project.config()[:aliases]), :publish)
  end
end
