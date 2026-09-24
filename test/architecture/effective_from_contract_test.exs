defmodule CharterAgreementProtocol.Architecture.EffectiveFromContractTest do
  @moduledoc false
  use ExUnit.Case, async: true

  test "the descriptor timestamp floor carries the same schema constraint as its siblings" do
    source = File.read!("lib/charter_agreement_protocol/party_descriptor.ex")

    needle =
      "Schema.field(\"effective_from\"," <>
        "\n                  required?: true," <>
        "\n                  types: [:string]," <>
        "\n                  constraint: {:string_bytes, 1, 64}\n                )"

    assert String.contains?(source, needle),
           "the effective_from floor is load-bearing: removing it reopens the last timestamp asymmetry"
  end
end
