defmodule CharterAgreementProtocol.ReceiptSignatureOutcomeTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Receipt}

  @signature_invalid {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}

  @substrate_unsupported {:error, Error.new(:algorithm_unsupported_on_substrate, ["signature", "ML-DSA-65"])}

  test "exactly one verified candidate key succeeds" do
    assert :ok = Receipt.signature_outcome([:ok])
    assert :ok = Receipt.signature_outcome([@signature_invalid, :ok])
  end

  test "no verified key and no substrate obstacle is signature_invalid" do
    assert @signature_invalid = Receipt.signature_outcome([@signature_invalid])
    assert @signature_invalid = Receipt.signature_outcome([@signature_invalid, @signature_invalid])
  end

  test "zero verified keys with a substrate obstacle reports the diagnostic honestly" do
    assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
             Receipt.signature_outcome([@substrate_unsupported])

    assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
             Receipt.signature_outcome([@substrate_unsupported, @signature_invalid])
  end

  test "one verified key among extra failing candidates still succeeds (the exact-one rule counts verifications)" do
    assert :ok = Receipt.signature_outcome([@signature_invalid, :ok, @substrate_unsupported])
  end

  test "two verified keys stay signature_invalid (no unique signer)" do
    assert {:error, %Error{code: :signature_invalid}} = Receipt.signature_outcome([:ok, :ok])
  end

  test "an empty candidate set fails closed" do
    assert @signature_invalid = Receipt.signature_outcome([])
  end
end
