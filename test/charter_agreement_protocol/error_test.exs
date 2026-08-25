defmodule CharterAgreementProtocol.ErrorTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.Error

  test "constructs only declared typed value-free failures" do
    assert %Error{code: :invalid_type, subject: ["json"], detail: nil} =
             Error.new(:invalid_type, ["json"])

    assert Error.declared?(:invalid_type)
    refute Error.declared?(:invented)
    assert_raise ArgumentError, fn -> Error.new(:invented, ["secret-value"]) end

    invalid_subject = Process.get(:invalid_subject_for_test, :not_a_subject)
    assert_raise ArgumentError, fn -> Error.new(:invalid_type, invalid_subject) end

    assert %Error{detail: :protocol_detail} =
             Error.new(:invalid_type, ["json"], :protocol_detail)

    assert %Error{detail: "protocol-detail"} =
             Error.new(:invalid_type, ["json"], "protocol-detail")

    invalid_detail = Process.get(:invalid_detail_for_test, {:secret, "do-not-echo"})
    assert_raise ArgumentError, fn -> Error.new(:invalid_type, ["json"], invalid_detail) end
  end

  test "the vocabulary is closed and duplicate-free" do
    assert Error.codes() == Enum.uniq(Error.codes())
    assert Enum.all?(Error.codes(), &is_atom/1)
  end
end
