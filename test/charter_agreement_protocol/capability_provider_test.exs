defmodule CharterAgreementProtocol.CapabilityProviderTest do
  use ExUnit.Case, async: false

  unless Code.ensure_loaded?(:cover) do
    :code.root_dir()
    |> List.to_string()
    |> Path.join("lib/tools-*/ebin")
    |> Path.wildcard()
    |> hd()
    |> Code.prepend_path()
  end

  Code.ensure_loaded!(:cover)
  alias CharterAgreementProtocol.Capability

  test "a real provider load failure returns an unavailable report" do
    directories = Path.wildcard("/usr/lib/*/libcrypto.so.3") |> Enum.map(&Path.dirname/1)
    library = Application.app_dir(:charter_agreement_protocol, "ebin")
    beam = Path.join(library, "Elixir.CharterAgreementProtocol.Capability.beam")
    declared = Capability.declared?("Ed25519")

    for directory <- directories do
      output_file =
        Path.join(
          System.tmp_dir!(),
          "cap-provider-#{System.unique_integer([:positive])}.coverdata"
        )

      on_exit(fn -> File.rm(output_file) end)

      code = """
      :cover.start()
      {:ok, _} = :cover.compile_beam(#{inspect(String.to_charlist(beam))})
      result = CharterAgreementProtocol.Capability.kat_verifies?("Ed25519", #{inspect(declared)})
      queries = for _ <- 1..32, do: Task.async(fn -> CharterAgreementProtocol.Capability.kat_verifies?("Ed25519") end)
      query_results = Enum.map(queries, &Task.await/1)
      report = CharterAgreementProtocol.Capability.report()
      if report.linked_crypto == [] do
        false = result
        true = Enum.all?(query_results, &(&1 == false))
        true = Enum.all?(report.algorithms, &(not &1.verifiable))
        IO.puts("provider result: unavailable")
      else
        IO.puts("provider result: loaded")
      end
      :ok = :cover.export(#{inspect(String.to_charlist(output_file))})
      """

      {output, status} =
        System.cmd("elixir", ["-pa", library, "-e", code],
          env: [{"LD_LIBRARY_PATH", directory}],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "provider result:"

      if Process.whereis(:cover_server),
        do: assert(:cover.import(String.to_charlist(output_file)) == :ok)
    end
  end

  test "partial metadata queries use the real runtime for the other axis" do
    assert Capability.declared?("Ed25519", :crypto.supports(:public_keys), nil)
    assert Capability.declared?("Ed25519", nil, :crypto.supports(:curves))
  end
end
