defmodule CharterAgreementProtocol.SupplierForkDemoTest do
  use ExUnit.Case, async: false

  test "the signed fork demo reports contest, receipt cross-check, and countersigned repair" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Code.eval_file("examples/supplier_fork_demo.exs")
      end)

    assert output =~ "equivocation: evidenced"
    assert output =~ "governing before repair: contested"
    assert output =~ "receipt chain conflict: none"
    assert output =~ "receipt governing match: undetermined"
    assert output =~ "receipt action outcome: effect_committed"
    assert output =~ "repair countersignatures: 2"
    assert output =~ "governing after repair: sha-256:"
    refute output =~ "governing after repair: contested"
    assert output =~ "CAP reports evidence; it does not adjudicate or authorize."
  end
end
