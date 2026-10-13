defmodule CharterAgreementProtocol.CapabilityLockTest do
  use ExUnit.Case, async: false

  test "the cache lock stays on this node when another node is connected" do
    library = Application.app_dir(:charter_agreement_protocol, "ebin")
    {_output, 0} = System.cmd("epmd", ["-daemon"])
    name = "cap_lock_#{System.unique_integer([:positive])}"

    code = """
    {:ok, peer, remote} = :peer.start_link(%{name: :cap_lock_peer, args: [~c"+S", ~c"2", ~c"-setcookie", ~c"cap_test_cookie"]})
    true = remote in Node.list()
    {true, calls} = CharterAgreementProtocol.CryptoTrace.count(:global, :set_lock, 3, fn ->
      CharterAgreementProtocol.Capability.kat_verifies?("Ed25519")
    end)
    true = calls != []
    IO.inspect(Enum.map(calls, fn [_id, nodes, _retries] -> nodes end), label: "lock nodes")
    true = Enum.all?(calls, fn [_id, nodes, _retries] -> nodes == [node()] end)
    :peer.stop(peer)
    IO.puts("cache lock: local node only")
    """

    {output, status} =
      System.cmd(
        "elixir",
        ["--sname", name, "--cookie", "cap_test_cookie", "-pa", library, "-e", code],
        env: [{"ERL_FLAGS", "+S 2"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "cache lock: local node only"
  end
end
