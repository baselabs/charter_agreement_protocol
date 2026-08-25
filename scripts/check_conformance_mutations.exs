defmodule CharterAgreementProtocol.ConformanceMutationGate do
  @root Path.expand("..", __DIR__)

  @mutations [
    %{
      name: "jcs-number-defeat",
      path: "lib/charter_agreement_protocol/canonicalization.ex",
      from: "      float == 0 -> {:ok, \"0\"}",
      to: "      false -> {:ok, \"0\"}",
      command: ~w(mix test test/charter_agreement_protocol/canonicalization_test.exs --seed 42)
    },
    %{
      name: "padding-acceptance",
      path: "lib/charter_agreement_protocol/base64url.ex",
      from: "      String.contains?(input, \"=\") ->",
      to: "      false ->",
      command: ~w(mix test test/charter_agreement_protocol/base64url_test.exs --seed 42)
    },
    %{
      name: "separator-collapse",
      path: "lib/charter_agreement_protocol/digest.ex",
      from: "def hash(domain, data), do: of([Map.fetch!(@separators, domain), <<0>>, data])",
      to: "def hash(_domain, data), do: of(data)",
      command: ~w(mix test test/charter_agreement_protocol/digest_test.exs --seed 42)
    },
    %{
      name: "unknown-member-acceptance",
      path: "lib/charter_agreement_protocol/schema.ex",
      from: "      with :ok <- reject_unknown(definition, member_map),",
      to: "      with :ok <- :ok,",
      command: ~w(mix test test/charter_agreement_protocol/schema_test.exs --seed 42)
    },
    %{
      name: "chain-signature-skip",
      path: "lib/charter_agreement_protocol/compact_jws.ex",
      from:
        "  def verify_signature(%__MODULE__{} = envelope, public_key),\n    do: Signature.verify(envelope.message, envelope.signature, public_key)",
      to: "  def verify_signature(%__MODULE__{} = _envelope, _public_key),\n    do: :ok",
      command: ~w(mix test test/charter_agreement_protocol/descriptor_chain_test.exs --seed 42)
    },
    %{
      name: "digest-equality-skip",
      path: "lib/charter_agreement_protocol/digest.ex",
      from: "      if equal?(hash(domain, bytes), declared),",
      to: "      if true,",
      command: ~w(mix test test/charter_agreement_protocol/digest_test.exs --seed 42)
    },
    %{
      name: "ed25519-defeat",
      path: "lib/charter_agreement_protocol/signature.ex",
      from: ":crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])",
      to: "not :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])",
      command: ~w(mix test test/charter_agreement_protocol/party_descriptor_test.exs --seed 42)
    },
    %{
      name: "typ-confusion",
      path: "lib/charter_agreement_protocol/compact_jws.ex",
      from: "        \"typ\" => {:string, ^expected_typ}",
      to: "        \"typ\" => {:string, _received_typ}",
      command: ~w(mix test test/charter_agreement_protocol/party_descriptor_test.exs --seed 42)
    },
    %{
      name: "reason-code-uncheck",
      path: "lib/charter_agreement_protocol/termination_notice.ex",
      from: "         termination.reason_code in revision.termination_rules.reason_codes do",
      to: "         true do",
      command: ~w(mix test test/charter_agreement_protocol/termination_notice_test.exs --seed 42)
    },
    %{
      name: "precedence-lowest",
      path: "lib/charter_agreement_protocol/chain.ex",
      from:
        "  defp select_candidates(candidates, accepted) do\n    maximum = candidates |> Enum.map(& &1.revision_number) |> Enum.max()",
      to:
        "  defp select_candidates(candidates, accepted) do\n    maximum = candidates |> Enum.map(& &1.revision_number) |> Enum.min()",
      command: ~w(mix test test/charter_agreement_protocol/chain_test.exs --seed 42)
    },
    %{
      name: "facts-union-suppression",
      path: "lib/charter_agreement_protocol/facts.ex",
      from: "Enum.uniq(@not_verified ++ additions)",
      to: "Enum.uniq(additions)",
      command: ~w(mix test test/architecture/facts_construction_test.exs --seed 42)
    },
    %{
      name: "fork-topology-suppressed",
      path: "lib/charter_agreement_protocol/chain.ex",
      from: "      if current_revision_fork?(accepted, superseded),",
      to: "      if false,",
      command: ~w(mix test test/charter_agreement_protocol/chain_test.exs --seed 42)
    },
    %{
      name: "contested-tie-resolved",
      path: "lib/charter_agreement_protocol/chain.ex",
      from: "      _siblings ->\n        :contested\n    end\n  end\n\n  defp linear_candidates?",
      to:
        "      [first | _siblings] ->\n        first.revision_digest\n    end\n  end\n\n  defp linear_candidates?",
      command: ~w(mix test test/charter_agreement_protocol/chain_test.exs --seed 42)
    },
    %{
      name: "acceptance-claims-mismatch-accept",
      path: "lib/charter_agreement_protocol/acceptance.ex",
      from: "         acceptance.revision_digest == revision_digest and",
      to: "         true and",
      command: ~w(mix test test/charter_agreement_protocol/acceptance_test.exs --seed 42)
    },
    %{
      name: "prev-binding-skip",
      path: "lib/charter_agreement_protocol/party_descriptor.ex",
      from: "         descriptor.prev_descriptor_digest == predecessor.descriptor_digest and",
      to: "         true and",
      command: ~w(mix test test/charter_agreement_protocol/party_descriptor_test.exs --seed 42)
    },
    %{
      name: "receipt-number-crosscheck-skip",
      path: "lib/charter_agreement_protocol/receipt.ex",
      from: "         receipt.revision_number == revision.revision_number and",
      to: "         true and",
      command: ~w(mix test test/charter_agreement_protocol/receipt_test.exs --seed 42)
    },
    %{
      name: "receipt-conflict-silenced",
      path: "lib/charter_agreement_protocol/receipt.ex",
      from:
        "      conflict = if receipt.revision_number <= accepted_head, do: :fork_evidenced, else: :none",
      to: "      conflict = :none",
      command: ~w(mix test test/charter_agreement_protocol/receipt_test.exs --seed 42)
    },
    %{
      name: "equivocation-guard-removed",
      path: "lib/charter_agreement_protocol/signing_input.ex",
      from: "    if conflict?, do: refused(), else: :ok",
      to: "    if false, do: refused(), else: :ok",
      command: ~w(mix test test/charter_agreement_protocol/signing_input_test.exs --seed 42)
    },
    %{
      name: "stale-branch-guard-removed",
      path: "lib/charter_agreement_protocol/signing_input.ex",
      from: "    if covered?, do: :ok, else: refused()",
      to: "    if true, do: :ok, else: refused()",
      command: ~w(mix test test/charter_agreement_protocol/signing_input_test.exs --seed 42)
    },
    %{
      name: "superseded-descriptor-silent-accept",
      path: "lib/charter_agreement_protocol/descriptor_chain.ex",
      from: "    position = if number == maximum, do: :head, else: :superseded",
      to: "    position = :head",
      command: ~w(mix test test/charter_agreement_protocol/descriptor_chain_test.exs --seed 42)
    },
    %{
      name: "supersession-ignore",
      path: "lib/charter_agreement_protocol/chain.ex",
      from: "    accepted\n    |> Enum.flat_map(& &1.revision.supersedes)\n    |> MapSet.new()",
      to: "    MapSet.new()",
      command: ~w(mix test test/charter_agreement_protocol/chain_test.exs --seed 42)
    },
    %{
      name: "corpus-expectation-flip",
      path: "priv/conformance/cases/base64url-decode.json",
      from: "\"expect\":{\"output\":{\"bytes_base64url\":\"\"},\"status\":\"valid\"}",
      to: "\"expect\":{\"error_code\":\"invalid_type\",\"status\":\"invalid\"}",
      command: ~w(mix conformance.verify)
    }
  ]

  @copy_paths [
    ".formatter.exs",
    "lib",
    "mix.exs",
    "mix.lock",
    "priv",
    "scripts",
    "test"
  ]

  def run do
    Enum.each(@mutations, &run_mutation/1)
    IO.puts("conformance mutation gate: ok mutations=#{length(@mutations)}")
  end

  defp run_mutation(mutation) do
    baseline_green!(mutation.command)
    scratch = temporary(mutation.name)

    try do
      Enum.each(@copy_paths, &copy_path(&1, scratch))
      File.ln_s!(Path.join(@root, "deps"), Path.join(scratch, "deps"))
      copy_build(scratch)
      mutate_once!(Path.join(scratch, mutation.path), mutation.from, mutation.to)

      {output, status} =
        System.cmd(hd(mutation.command), tl(mutation.command),
          cd: scratch,
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "test"}]
        )

      if status == 0, do: raise("mutation survived: #{mutation.name}\n#{output}")
      IO.puts("mutation caught: #{mutation.name}")
    after
      File.rm_rf!(scratch)
    end
  end

  defp baseline_green!(command) do
    key = {:baseline_green, command}

    if Process.get(key) != :ok do
      {output, status} =
        System.cmd(hd(command), tl(command),
          cd: @root,
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "test"}]
        )

      if status != 0, do: raise("baseline not green: #{Enum.join(command, " ")}\n#{output}")
      Process.put(key, :ok)
    end
  end

  defp copy_path(relative, scratch) do
    source = Path.join(@root, relative)
    target = Path.join(scratch, relative)
    File.mkdir_p!(Path.dirname(target))
    {:ok, _copied} = File.cp_r(source, target)
  end

  defp copy_build(scratch) do
    source = Path.join(@root, "_build/test")

    if File.dir?(source) do
      target = Path.join(scratch, "_build/test")
      File.mkdir_p!(Path.dirname(target))
      {:ok, _copied} = File.cp_r(source, target)
    end
  end

  defp mutate_once!(path, source, replacement) do
    bytes = File.read!(path)

    if length(:binary.matches(bytes, source)) != 1,
      do: raise("mutation anchor is not exact: #{path}")

    File.write!(path, String.replace(bytes, source, replacement))
  end

  defp temporary(name) do
    path =
      Path.join(
        System.tmp_dir!(),
        "cap-mutation-#{name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end

CharterAgreementProtocol.ConformanceMutationGate.run()
