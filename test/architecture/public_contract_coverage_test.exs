defmodule CharterAgreementProtocol.Architecture.PublicContractCoverageTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  test "every explicit production module states the boundary and every public head has a spec" do
    assert ArchitectureScan.public_contract_findings() == []
  end

  test "missing stance and missing public specs make the contract gate red" do
    missing_stance = """
    defmodule Example do
      @moduledoc "Codec helpers."
      @spec decode(binary()) :: binary()
      def decode(bytes), do: bytes
    end
    """

    missing_spec = """
    defmodule Example do
      @moduledoc "Pure facts only; this module never authorizes."
      def decode(bytes), do: bytes
    end
    """

    assert {:missing_stance, Example} in ArchitectureScan.source_contract_findings(missing_stance)

    assert {:missing_spec, Example, :decode, 1} in ArchitectureScan.source_contract_findings(
             missing_spec
           )
  end

  test "multiple top-level modules cannot hide behind a file-level block" do
    source = """
    defmodule First do
      @moduledoc "Codec helpers."
    end

    defmodule Second do
      @moduledoc "More codec helpers."
    end
    """

    findings = ArchitectureScan.source_contract_findings(source)

    assert {:missing_stance, First} in findings
    assert {:missing_stance, Second} in findings
  end
end
