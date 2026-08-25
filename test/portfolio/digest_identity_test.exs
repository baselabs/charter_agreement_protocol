defmodule CharterAgreementProtocol.Portfolio.DigestIdentityTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{CharterRevisionFixture, Digest, ReceiptFixture}

  @deployment_bytes File.read!(
                      Path.expand(
                        "../../deps/agent_blueprint_protocol/priv/conformance/vectors/deployment-golden.json",
                        __DIR__
                      )
                    )

  test "CAP grant digest binds the exact BAP ath bytes" do
    compact_module = bap_module("CompactJws")
    bounds_module = bap_module("Bounds")
    limits = bounds_module.maximum()

    assert {:ok, ath} = compact_module.ath(ReceiptFixture.grant_compact(), limits)

    assert {:ok, raw_hash} = compact_module.hash(ReceiptFixture.grant_compact(), limits)

    assert ath == ReceiptFixture.grant_ath()
    assert ReceiptFixture.grant_digest() == "sha-256:" <> ath
    assert {:ok, %Digest{bytes: ^raw_hash}} = Digest.from_tagged(ReceiptFixture.grant_digest())
  end

  test "portfolio dependencies are exact, test-only, runtime-disabled Hex identities" do
    dependencies = Mix.Project.config()[:deps]

    assert {:agent_blueprint_protocol, "== 0.1.1", only: [:dev, :test], runtime: false} in dependencies

    assert {:bounded_authority_protocol, "== 0.1.2", only: [:dev, :test], runtime: false} in dependencies

    lock = File.read!("mix.lock")
    assert lock =~ ~s("agent_blueprint_protocol": {:hex, :agent_blueprint_protocol, "0.1.1")
    assert lock =~ "bd9b3b5f505489e02490fb44dbc52c74c347346519d7455eb6744a3832de318b"
    assert lock =~ ~s("bounded_authority_protocol": {:hex, :bounded_authority_protocol, "0.1.2")
    assert lock =~ "fc9496c8bb37f9577d13e51621174ca40a3bb8f3fa49456c8c878fe61205ba22"
  end

  test "CAP ABP binding fixture equals the exact published ABP deployment output" do
    assert {:ok, deployment} = AgentBlueprintProtocol.decode_deployment(@deployment_bytes)
    digest = AgentBlueprintProtocol.Deployment.content_digest(deployment)
    tagged = AgentBlueprintProtocol.Digest.to_tagged(digest)

    assert tagged == CharterRevisionFixture.abp_deployment_digest()

    assert {:string, ^tagged} =
             deployment
             |> AgentBlueprintProtocol.Deployment.to_value()
             |> object_member("deployment_digest")

    assert {:object, release} =
             deployment
             |> AgentBlueprintProtocol.Deployment.to_value()
             |> object_member("blueprint_release")

    assert {:string, content_digest} = List.keyfind(release, "content_digest", 0) |> elem(1)
    assert content_digest == CharterRevisionFixture.abp_content_digest()
  end

  defp object_member({:object, members}, name), do: List.keyfind(members, name, 0) |> elem(1)

  defp bap_module(leaf),
    do: Module.concat([BoundedAuthorityProtocol, "V" <> Integer.to_string(1), leaf])
end
