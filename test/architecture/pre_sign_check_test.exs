defmodule CharterAgreementProtocol.Architecture.PreSignCheckTest do
  @moduledoc false
  use ExUnit.Case, async: true

  test "verification and signing use the same preparation paths" do
    for module <- ["party_descriptor", "acceptance", "termination_notice", "receipt"] do
      source = File.read!("lib/charter_agreement_protocol/#{module}.ex")
      assert source =~ "def prepare("
      assert source =~ "<- prepare(compact,"
    end

    source = File.read!("lib/charter_agreement_protocol/signing_plan.ex")

    for module <- ["PartyDescriptor", "Acceptance", "TerminationNotice", "Receipt"] do
      assert source =~ "#{module}.prepare("
    end

    chain = File.read!("lib/charter_agreement_protocol/chain.ex")
    assert length(Regex.scan(~r/defp lookup_context\(/, chain)) == 1
    assert length(Regex.scan(~r/<-\s+lookup_context\(/, chain)) == 2
    assert source =~ "Chain.signing_context(kind, artifact, chain)"
  end

  test "key shape and cached runtime checks have one owner" do
    signature = File.read!("lib/charter_agreement_protocol/signature.ex")
    assert signature =~ "valid_key?(public_key, key_algorithm)"
    capability = File.read!("lib/charter_agreement_protocol/capability.ex")
    assert capability =~ ":persistent_term.get(cache_key, :missing)"
    assert capability =~ ":persistent_term.put(cache_key, result)"
    assert capability =~ "verifiable: declared and safe_known_answer(key_algorithm)"
  end

  test "the facade adds exactly the two explicit signing calls" do
    exports = CharterAgreementProtocol.__info__(:functions)
    assert {:prepare_signing, 5} in exports
    assert {:finish_signing, 2} in exports
    refute {:prepare_signing, 4} in exports
    refute {:assemble_compact, 3} in exports
  end
end
