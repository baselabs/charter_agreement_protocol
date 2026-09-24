defmodule CharterAgreementProtocol.Architecture.ProfileContractTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.Capability.Profile

  test "the profile surface is threaded, not pre-passed: every verify seam takes a profile" do
    for {path, anchors} <- [
          {"lib/charter_agreement_protocol/compact_jws.ex",
           [
             "verify_signature(%__MODULE__{} = envelope, public_key, key_algorithm, %Profile{} = profile)"
           ]},
          {"lib/charter_agreement_protocol/chain.ex",
           ["%Profile{} = profile", "revision_profile(revisions, profile)"]},
          {"lib/charter_agreement_protocol/acceptance.ex",
           [
             "CompactJws.verify_signature(acceptance.envelope, key.public_key, key.algorithm, profile)"
           ]},
          {"lib/charter_agreement_protocol/termination_notice.ex",
           [
             "CompactJws.verify_signature(termination.envelope, key.public_key, key.algorithm, profile)"
           ]},
          {"lib/charter_agreement_protocol/party_descriptor.ex",
           [
             "CompactJws.verify_signature(descriptor.envelope, public_key, key_algorithm, profile)"
           ]},
          {"lib/charter_agreement_protocol/receipt.ex",
           ["CompactJws.verify_signature(receipt.envelope, public_key, algorithm, profile)"]}
        ] do
      # Whitespace-insensitive: the formatter reflows call arguments
      # differently per file, so both source and anchor are compacted by
      # the same normalizer before matching.
      compact = &String.replace(&1, ~r/\s+/, "")
      source = File.read!(path) |> compact.()

      for anchor <- anchors do
        assert String.contains?(source, compact.(anchor)),
               "missing profile threading anchor in #{path}: #{anchor}"
      end
    end
  end

  test "the profile decision is admission at the signature seam, before crypto" do
    source = File.read!("lib/charter_agreement_protocol/compact_jws.ex")

    assert String.contains?(
             source,
             "with :ok <- admit(envelope, profile) do"
           ),
           "the admission gate must run inside verify_signature before dispatch"
  end

  test "the gate is red when a seam drops its profile threading" do
    source = File.read!("lib/charter_agreement_protocol/acceptance.ex")

    refute String.contains?(
             source,
             "CompactJws.verify_signature(acceptance.envelope, key.public_key, key.algorithm)"
           ),
           "an unprofiled verify_signature call at the acceptance seam means the profile is not threaded"
  end
end
