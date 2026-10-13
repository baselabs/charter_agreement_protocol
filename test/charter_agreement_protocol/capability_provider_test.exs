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
    library = Application.app_dir(:charter_agreement_protocol, "ebin")
    beam = Path.join(library, "Elixir.CharterAgreementProtocol.Capability.beam")
    signature_beam = Path.join(library, "Elixir.CharterAgreementProtocol.Signature.beam")
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    signature = :crypto.sign(:eddsa, :none, "provider", [private, :ed25519])
    directory = Path.join(System.tmp_dir!(), "cap-provider-#{System.unique_integer([:positive])}")
    crypto = :code.lib_dir(:crypto) |> List.to_string()
    isolated = Path.join(directory, Path.basename(crypto))
    output_file = Path.join(directory, "provider.coverdata")
    File.mkdir_p!(isolated)
    File.cp_r!(Path.join(crypto, "ebin"), Path.join(isolated, "ebin"))
    on_exit(fn -> File.rm_rf!(directory) end)

    # OTP's unchanged crypto modules run without their native library in a child VM.
    code = """
    #{inspect(String.to_charlist(Path.join(isolated, "priv")))} = :code.priv_dir(:crypto)
    try do
      :crypto.supports()
      raise "the isolated crypto application unexpectedly loaded its native library"
    rescue
      UndefinedFunctionError -> :ok
    end
    :cover.start()
    {:ok, _} = :cover.compile_beam(#{inspect(String.to_charlist(beam))})
    {:ok, _} = :cover.compile_beam(#{inspect(String.to_charlist(signature_beam))})
    true = CharterAgreementProtocol.Signature.valid_key?(#{inspect(public)}, "Ed25519")
    false = CharterAgreementProtocol.Capability.kat_verifies?("Ed25519", true)
    queries = for _ <- 1..32, do: Task.async(fn -> CharterAgreementProtocol.Capability.kat_verifies?("Ed25519") end)
    query_results = Enum.map(queries, &Task.await/1)
    {:error, %{code: :algorithm_unsupported_on_substrate}} = CharterAgreementProtocol.Signature.verify("provider", #{inspect(signature)}, #{inspect(public)}, "Ed25519")
    report = CharterAgreementProtocol.Capability.report()
    [] = report.linked_crypto
    true = Enum.all?(query_results, &(&1 == false))
    true = Enum.all?(report.algorithms, &(not &1.verifiable))
    IO.puts("provider result: unavailable")
    :ok = :cover.export(#{inspect(String.to_charlist(output_file))})
    """

    {output, status} =
      System.cmd("elixir", ["-pa", library, "-pa", Path.join(isolated, "ebin"), "-e", code],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "provider result: unavailable"

    if Process.whereis(:cover_server),
      do: assert(:cover.import(String.to_charlist(output_file)) == :ok)
  end

  test "partial metadata queries use the real runtime for the other axis" do
    assert Capability.declared?("Ed25519", :crypto.supports(:public_keys), nil)
    assert Capability.declared?("Ed25519", nil, :crypto.supports(:curves))
  end
end
