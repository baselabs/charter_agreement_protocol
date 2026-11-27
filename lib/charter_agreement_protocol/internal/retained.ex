defmodule CharterAgreementProtocol.Internal.Retained do
  @moduledoc "Retained byte extraction for re-verification. CAP never authorizes."

  alias CharterAgreementProtocol.{
    Base64Url,
    CharterRevision,
    CompactJws,
    DescriptorChain,
    DescriptorFacts,
    Error,
    ForkEvidence,
    PartyDescriptor
  }

  @spec list?(term()) :: boolean()
  def list?([]), do: true
  def list?([_item | rest]), do: list?(rest)
  def list?(_other), do: false

  @spec binaries?(term()) :: boolean()
  def binaries?([]), do: true
  def binaries?([item | rest]) when is_binary(item), do: binaries?(rest)
  def binaries?(_other), do: false

  @spec compact(term()) :: {:ok, binary()} | :error
  def compact(%CompactJws{message: message, signature: signature})
      when is_binary(message) and is_binary(signature),
      do: {:ok, message <> "." <> Base64Url.encode(signature)}

  def compact(_other), do: :error
  @spec check(term(), term()) :: :ok | {:error, Error.t()}
  def check(supplied, verified) do
    if compatible?(supplied, verified),
      do: :ok,
      else: {:error, Error.new(:invalid_type, ["context"])}
  end

  @spec verified_context?(term(), term()) :: boolean()
  def verified_context?(revision, chain), do: revision_shape?(revision) and chain_shape?(chain)

  @doc false
  @spec revision_shape?(term()) :: boolean()
  def revision_shape?(%CharterRevision{} = revision) do
    Map.keys(revision) == Map.keys(struct(CharterRevision)) and
      is_binary(revision.canonical_bytes) and is_integer(revision.revision_number) and
      optional_binary?(revision.charter_id) and optional_binary?(revision.prev_revision_digest) and
      binaries?(revision.supersedes) and
      list?(revision.parties) and
      Enum.all?(revision.parties, &party_shape?/1) and
      revision_rules_shape?(revision)
  end

  def revision_shape?(_other), do: false

  defp revision_rules_shape?(revision) do
    optional_quorum_shape?(revision.acceptance_quorum) and
      replacements_shape?(revision.party_replacements) and
      rules_shape?(revision.termination_rules)
  end

  defp party_shape?(%CharterRevision.Party{role: role, party_descriptor_digest: digest} = party) do
    complete?(party, CharterRevision.Party) and is_binary(role) and is_binary(digest) and
      party.participation in [nil, "acceptor", "arbiter"]
  end

  defp party_shape?(_other), do: false

  defp rules_shape?(%CharterRevision.TerminationRules{reason_codes: codes} = rules),
    do:
      complete?(rules, CharterRevision.TerminationRules) and binaries?(codes) and
        optional_quorum_shape?(rules.quorum)

  defp rules_shape?(_other), do: false

  defp optional_quorum_shape?(nil), do: true
  defp optional_quorum_shape?(rule), do: quorum_shape?(rule)

  defp quorum_shape?(%{roles: roles, threshold: threshold} = rule) when map_size(rule) == 2 do
    binaries?(roles) and is_integer(threshold) and threshold >= 0 and threshold <= length(roles)
  end

  defp quorum_shape?(_rule), do: false

  defp replacements_shape?(records),
    do: list?(records) and Enum.all?(records, &replacement_shape?/1)

  defp replacement_shape?(
         %{
           role: role,
           assignor_party_id: owner,
           assignor_descriptor_digest: from,
           assignee_descriptor_digest: to,
           assent_quorum: quorum
         } = record
       )
       when map_size(record) == 5 do
    is_binary(role) and is_binary(owner) and is_binary(from) and is_binary(to) and
      quorum_shape?(quorum)
  end

  defp replacement_shape?(_record), do: false

  defp chain_shape?(%DescriptorChain{} = chain) do
    Map.keys(chain) == Map.keys(%DescriptorChain{topology: :linear, descriptors: []}) and
      chain.topology in [:linear, :forked] and list?(chain.descriptors) and
      Enum.all?(chain.descriptors, &descriptor_facts_shape?/1) and
      (is_nil(chain.fork_evidence) or is_struct(chain.fork_evidence, ForkEvidence))
  end

  defp chain_shape?(_other), do: false

  defp descriptor_facts_shape?(
         %DescriptorFacts{
           descriptor_digest: digest,
           descriptor_position: position,
           descriptor: descriptor
         } = facts
       ) do
    complete?(facts, DescriptorFacts) and is_binary(digest) and
      position in [:head, :superseded, :contested] and descriptor_shape?(descriptor)
  end

  defp descriptor_facts_shape?(_other), do: false

  defp descriptor_shape?(%PartyDescriptor{verification_keys: keys} = descriptor) do
    complete?(descriptor, PartyDescriptor) and list?(keys) and Enum.all?(keys, &key_shape?/1) and
      optional_binary?(descriptor.next_key_commitment) and
      (is_nil(descriptor.signing_scopes) or scopes_shape?(descriptor.signing_scopes))
  end

  defp descriptor_shape?(_other), do: false

  defp scopes_shape?(scopes), do: list?(scopes) and Enum.all?(scopes, &scope_shape?/1)

  defp scope_shape?(%{role: role, signers: signers} = scope) when map_size(scope) == 2 do
    is_binary(role) and list?(signers) and Enum.all?(signers, &scope_signer_shape?/1)
  end

  defp scope_shape?(_scope), do: false

  defp scope_signer_shape?(%{key_thumbprint: thumbprint, artifact_kinds: kinds} = signer)
       when map_size(signer) == 2 do
    is_binary(thumbprint) and binaries?(kinds)
  end

  defp scope_signer_shape?(_signer), do: false

  defp key_shape?(
         %PartyDescriptor.VerificationKey{
           key_id: id,
           public_key: public,
           algorithm: algorithm,
           status: status
         } = key
       ) do
    complete?(key, PartyDescriptor.VerificationKey) and is_binary(id) and is_binary(public) and
      is_binary(algorithm) and status in [:active, :retired]
  end

  defp key_shape?(_other), do: false

  defp complete?(value, module), do: Map.keys(value) == Map.keys(struct(module))
  defp optional_binary?(nil), do: true
  defp optional_binary?(value), do: is_binary(value)

  @spec compatible?(term(), term()) :: boolean()
  def compatible?(%{__struct__: module} = supplied, %{__struct__: module} = verified) do
    Map.keys(supplied) == Map.keys(verified) and
      Enum.all?(Map.from_struct(verified), fn {field, value} ->
        optional_scalar?(module, field, Map.get(supplied, field)) or
          field_shape?(field, Map.get(supplied, field), value)
      end)
  end

  def compatible?(supplied, verified) when is_binary(verified), do: is_binary(supplied)
  def compatible?(supplied, verified) when is_integer(verified), do: is_integer(supplied)
  def compatible?(supplied, verified) when is_float(verified), do: is_float(supplied)
  def compatible?(supplied, nil), do: is_nil(supplied)
  def compatible?(supplied, verified) when is_boolean(verified), do: is_boolean(supplied)
  def compatible?(supplied, verified) when is_atom(verified), do: is_atom(supplied)

  def compatible?(supplied, verified) when is_list(verified) do
    if list?(supplied) and list?(verified) do
      models = Enum.uniq_by(verified, &shape/1)
      Enum.all?(supplied, fn item -> Enum.any?(models, &compatible?(item, &1)) end)
    else
      false
    end
  end

  def compatible?(supplied, verified) when is_tuple(verified) do
    is_tuple(supplied) and tuple_size(supplied) == tuple_size(verified) and
      Enum.all?(Enum.zip(Tuple.to_list(supplied), Tuple.to_list(verified)), fn {value, model} ->
        compatible?(value, model)
      end)
  end

  def compatible?(_supplied, _verified), do: false

  defp shape(%{__struct__: module} = value) do
    {module,
     value
     |> Map.from_struct()
     |> Enum.map(fn {field, item} -> {field, shape(item)} end)
     |> Enum.sort()}
  end

  defp shape(value) when is_list(value), do: {:list, value |> Enum.map(&shape/1) |> MapSet.new()}

  defp shape(value) when is_tuple(value),
    do: {:tuple, value |> Tuple.to_list() |> Enum.map(&shape/1)}

  defp shape(value) when is_binary(value), do: :binary
  defp shape(value) when is_integer(value), do: :integer
  defp shape(value) when is_float(value), do: :float
  defp shape(nil), do: nil
  defp shape(value) when is_boolean(value), do: :boolean
  defp shape(value) when is_atom(value), do: :atom
  defp shape(_value), do: :other

  defp optional_scalar?(module, field, nil) when field in [:alg, :protocol_revision],
    do:
      module in [
        CharterAgreementProtocol.DescriptorFacts,
        CharterAgreementProtocol.AcceptanceFacts,
        CharterAgreementProtocol.TerminationFacts,
        CharterAgreementProtocol.RevisionFacts
      ]

  defp optional_scalar?(_module, _field, _value), do: false

  defp field_shape?(field, supplied, _verified)
       when field in [
              :lineage,
              :optional_extensions_retained,
              :accepted_revision_digests,
              :superseded_revision_digests,
              :supersedes,
              :reason_codes,
              :sibling_descriptors,
              :revision_digests,
              :acceptance_digests
            ],
       do: binaries?(supplied)

  defp field_shape?(field, supplied, verified) when field in [:acceptance_quorum, :quorum] do
    if is_nil(verified), do: is_nil(supplied), else: quorum_shape?(supplied)
  end

  defp field_shape?(:party_replacements, supplied, _verified), do: replacements_shape?(supplied)

  defp field_shape?(:signing_scopes, supplied, nil), do: is_nil(supplied)
  defp field_shape?(:signing_scopes, supplied, _verified), do: scopes_shape?(supplied)

  defp field_shape?(:not_verified, supplied, _verified),
    do: list?(supplied) and Enum.all?(supplied, &is_atom/1)

  defp field_shape?(:chain_topology, supplied, _verified), do: supplied in [:linear, :forked]
  defp field_shape?(:topology, supplied, _verified), do: supplied in [:linear, :forked]

  defp field_shape?(:descriptor_position, supplied, _verified),
    do: supplied in [:head, :superseded, :contested]

  defp field_shape?(field, supplied, nil)
       when field in [
              :charter_id,
              :party_id,
              :prev_revision_digest,
              :prev_descriptor_digest,
              :uri_hint,
              :detail_digest
            ],
       do: is_nil(supplied) or is_binary(supplied)

  defp field_shape?(:effective_until, supplied, nil),
    do: is_nil(supplied) or is_struct(supplied, DateTime)

  defp field_shape?(_field, supplied, verified), do: compatible?(supplied, verified)
end
