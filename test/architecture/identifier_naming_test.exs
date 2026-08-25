defmodule CharterAgreementProtocol.Architecture.IdentifierNamingTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  @token_fixtures ~w(
    V2 v1 V2Codec CodecV2 CodecV2Parser
    decode_v2 decode_v2beta schema_v1 artifact_v2 artifactV2
    Es6Number Http2Stream Tls12Socket Query2 Schema3Parser
    HTTP2Stream TLS12Socket ES6Number
  )

  @clean_fixtures ~w(
    CharterAgreementProtocol Base64Url Ed25519 Sha256
    crypto Ipv4 IPV4 IPv4 IPv6 revision canonical
  )

  test "every conventional implementation-version form is rejected" do
    for name <- @token_fixtures do
      assert ArchitectureScan.version_token?(name), "expected hostile fixture to be rejected"
    end
  end

  test "protocol names and external algorithm names are accepted" do
    for name <- @clean_fixtures do
      refute ArchitectureScan.version_token?(name), "unexpected clean-identifier rejection"
    end
  end

  test "only the exact package source identity may carry a version token" do
    assert :ok =
             ArchitectureScan.check_durable_identifier(%{
               path: "mix.exs",
               kind: :package_source_ref,
               name: ~S(source_ref: "v#{@version}")
             })

    for fixture <- [
          %{
            path: "docs/package.exs",
            kind: :package_source_ref,
            name: ~S(source_ref: "v#{@version}")
          },
          %{path: "mix.exs", kind: :package_source_ref, name: ~S(source_ref: "v2")},
          %{path: "lib/protocol/v2.ex", kind: :path, name: "v2"},
          %{path: "lib/protocol.ex", kind: :module, name: "Protocol.V2"},
          %{path: "lib/protocol.ex", kind: :function, name: "decode_v2"},
          %{path: "test/protocol_v2_test.exs", kind: :path, name: "protocol_v2_test"}
        ] do
      assert {:error, :implementation_version_identifier} =
               ArchitectureScan.check_durable_identifier(fixture)
    end
  end

  test "the actual owned tree contains no version-bearing durable identifier" do
    identifier_offenders =
      for path <- ArchitectureScan.source_files(),
          {kind, name} <- ArchitectureScan.identifiers(path),
          {:error, :implementation_version_identifier} <- [
            ArchitectureScan.check_durable_identifier(%{path: path, kind: kind, name: name})
          ],
          do: {path, kind, name}

    path_offenders =
      for segment <- ArchitectureScan.path_segments(),
          {:error, :implementation_version_identifier} <- [
            ArchitectureScan.check_durable_identifier(%{
              path: segment,
              kind: :path,
              name: segment
            })
          ],
          do: segment

    assert identifier_offenders == []
    assert path_offenders == []
  end

  test "the real package metadata exposes exactly the blessed source identity" do
    assert ArchitectureScan.package_source_ref_observations() == [
             %{path: "mix.exs", kind: :package_source_ref, name: ~S(source_ref: "v#{@version}")}
           ]
  end
end
