defmodule CharterAgreementProtocol.CapabilityLaneTest do
  @moduledoc false
  # The capability-limited lane's assertions, written substrate-neutrally so
  # the SAME test is green on a capable substrate and on a limited one
  # (Ubuntu 24.04 / OpenSSL 3.0.13): the probe's verdicts must agree with
  # actual verification behavior, and verification under a declared
  # capability obstacle fails with the honest named diagnostic, never a
  # forgery verdict.
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Capability, Capability.Profile, Chain, ChainFixture, Error, Limits, Signature}

  test "the report's per-row verdicts agree with actual verification behavior" do
    for %{key_algorithm: key_algorithm, verifiable: verifiable?} <- Capability.report().algorithms do
      assert verifiable? == Capability.kat_verifies?(key_algorithm)
    end
  end

  test "ed25519 artifacts verify green on every substrate this suite runs on" do
    assert Capability.kat_verifies?("Ed25519")

    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<7>>, 32))
    message = "lane"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    assert :ok = Signature.verify(message, signature, public_key, "EdDSA")
  end

  test "ml-dsa verification honors the substrate honestly: green where capable, the named diagnostic where not" do
    if Capability.kat_verifies?("ML-DSA-65") do
      {public_key, private_key} = :crypto.generate_key(:mldsa65, [])
      message = "lane"
      signature = :crypto.sign(:mldsa65, :none, message, {:expandedkey, private_key})
      assert :ok = Signature.verify(message, signature, public_key, "ML-DSA-65")
    else
      # Key generation itself is impossible on this substrate; the honest
      # failure is reachable with right-length bytes because the substrate
      # gate fires after the deterministic length checks, before crypto.
      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
               Signature.verify("lane", <<0::3309*8>>, <<0::1952*8>>, "ML-DSA-65")
    end
  end

  test "an ed25519-profiled view verifies identically on every substrate" do
    setup = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)

    {:ok, profile} = Profile.new(algorithms: ["EdDSA"], revisions: {1, 1})

    assert {:ok, _facts} =
             Chain.verify(
               [setup.genesis.bytes],
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [],
               Limits.default(),
               profile
             )
  end
end

defmodule CharterAgreementProtocol.CapabilityLaneProbe do
  @moduledoc false
  # Informational lane output: the runtime's capability report, printed so a
  # lane log carries the substrate's declared verdicts alongside the
  # assertions above.
  use ExUnit.Case, async: true

  test "lane information: capability report" do
    report = CharterAgreementProtocol.capabilities()

    lines =
      for row <- report.algorithms do
        "#{row.name} (#{row.key_algorithm}): #{if row.verifiable, do: "verifiable", else: "NOT verifiable"}"
      end

    IO.puts(["capability lane report" | lines] |> Enum.join("\n"))
    assert is_list(report.algorithms)
  end
end
