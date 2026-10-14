defmodule CharterAgreementProtocol.IntegerClaimsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Internal.IntegerClaims}

  test "a float release_number inside a binding is a type error" do
    revision =
      {:object,
       [
         {"protocol_revision", {:integer, 2}},
         {"abp_bindings", {:array, [{:object, [{"release_number", {:float, 1.0}}]}]}}
       ]}

    assert {:error, %Error{code: :invalid_type}} =
             IntegerClaims.check(:charter_revision, revision)
  end

  test "binding entries that are not objects are left to the schema" do
    revision =
      {:object,
       [
         {"protocol_revision", {:integer, 2}},
         {"abp_bindings", {:array, [{:string, "not an object"}, {:integer, 1}]}}
       ]}

    assert :ok = IntegerClaims.check(:charter_revision, revision)
  end
end
