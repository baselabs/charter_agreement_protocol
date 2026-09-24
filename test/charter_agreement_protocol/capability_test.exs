defmodule CharterAgreementProtocol.CapabilityTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Algorithm, Capability, Error}

  test "report carries one verifiable verdict per registry row plus linked-crypto facts" do
    report = Capability.report()

    assert [{_name, _version_number, _version_string} | _] = report.linked_crypto

    assert length(report.algorithms) == length(Algorithm.registry())

    for row <- report.algorithms do
      assert %{name: name, key_algorithm: key_algorithm, verifiable: verifiable?} = row
      assert is_boolean(verifiable?)
      assert registry_row = Algorithm.row_for(name)
      assert registry_row.key_algorithm == key_algorithm
    end

    # Mixed-algorithm verdicts are per key algorithm, not one global boolean:
    # every registry key algorithm appears in the report.
    reported_key_algorithms =
      report.algorithms |> Enum.map(& &1.key_algorithm) |> Enum.uniq() |> Enum.sort()

    assert reported_key_algorithms ==
             Algorithm.registry() |> Enum.map(& &1.key_algorithm) |> Enum.uniq() |> Enum.sort()
  end

  test "every pinned known-answer vector verifies on this substrate" do
    for key_algorithm <- ["Ed25519", "ML-DSA-44", "ML-DSA-65", "ML-DSA-87"] do
      assert Capability.kat_verifies?(key_algorithm)
    end
  end

  test "declared? reads the runtime's declared public-key algorithms, both axes" do
    assert Capability.declared?("Ed25519", [:eddsa], [:ed25519])
    refute Capability.declared?("Ed25519", [:eddsa], [:ecdh])
    refute Capability.declared?("Ed25519", [:rsa], [:ed25519])
    assert Capability.declared?("ML-DSA-65", [:mldsa65], [])
    refute Capability.declared?("ML-DSA-65", [:rsa, :eddsa], [])
    # Unknown key algorithms are never declared.
    refute Capability.declared?("ML-DSA-99", [:mldsa65], [])
  end

  test "kat_verifies? is declaration-gated: no crypto call when undeclared" do
    # The second argument injects the substrate declaration; a raise inside the
    # gate would prove the call was made anyway.
    refute Capability.kat_verifies?("ML-DSA-65", false)
  end

  test "the facade mirrors the report" do
    assert CharterAgreementProtocol.capabilities() == Capability.report()
  end

  test "report verdicts agree with actual verification behavior on this substrate" do
    for %{key_algorithm: key_algorithm, verifiable: verifiable?} <- Capability.report().algorithms do
      assert verifiable? == Capability.kat_verifies?(key_algorithm)
    end
  end

  test "the substrate diagnostic is a declared error code" do
    assert Error.declared?(:algorithm_unsupported_on_substrate)
  end
end
