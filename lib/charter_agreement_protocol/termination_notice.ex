defmodule CharterAgreementProtocol.TerminationNotice do
  @moduledoc """
  Closed termination-notice codec and evidence verifier.

  Verification proves one pinned charter party signed a listed termination
  reason and pure effective-time coordinate. It does not read a clock or apply
  legal, receipt, delivery, or governance-effect policy.
  """

  alias CharterAgreementProtocol.{
    CharterRevision,
    CompactJws,
    DescriptorChain,
    DescriptorFacts,
    Digest,
    Error,
    Facts,
    Limits,
    PartyDescriptor,
    Schema,
    TerminationFacts,
    Timestamp
  }

  @enforce_keys [
    :protocol_revision,
    :charter_id,
    :governing_revision_digest,
    :party_descriptor_digest,
    :party_role,
    :reason_code,
    :effective_at,
    :issued_at,
    :envelope
  ]
  defstruct [
    :protocol_revision,
    :charter_id,
    :governing_revision_digest,
    :party_descriptor_digest,
    :party_role,
    :reason_code,
    :effective_at,
    :issued_at,
    :detail_digest,
    :envelope
  ]

  @type t :: %__MODULE__{
          protocol_revision: 1,
          charter_id: binary(),
          governing_revision_digest: binary(),
          party_descriptor_digest: binary(),
          party_role: binary(),
          reason_code: binary(),
          effective_at: Timestamp.t(),
          issued_at: Timestamp.t(),
          detail_digest: nil | binary(),
          envelope: CompactJws.t()
        }

  @tagged_digest ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/

  @definition Schema.definition("termination", [
                Schema.field("protocol_revision",
                  required?: true,
                  types: [:integer],
                  constraint: {:integer_range, 1, 1}
                ),
                Schema.field("charter_id",
                  required?: true,
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                ),
                Schema.field("governing_revision_digest",
                  required?: true,
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                ),
                Schema.field("party_descriptor_digest",
                  required?: true,
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                ),
                Schema.field("party_role",
                  required?: true,
                  types: [:string],
                  constraint: {:string_bytes, 1, 128}
                ),
                Schema.field("reason_code",
                  required?: true,
                  types: [:string],
                  constraint: {:string_bytes, 1, 128}
                ),
                Schema.field("effective_at", required?: true, types: [:string]),
                Schema.field("issued_at", required?: true, types: [:string]),
                Schema.field("detail_digest",
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                )
              ])

  @doc "Verify one attached termination notice against exact caller-supplied artifacts."
  @spec verify(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t()) ::
          {:ok, TerminationFacts.t()} | {:error, Error.t()}
  def verify(
        compact,
        %CharterRevision{} = supplied_revision,
        %DescriptorChain{} = supplied_chain,
        %Limits{} = limits
      ) do
    if Limits.valid?(limits) do
      do_verify(compact, supplied_revision, supplied_chain, limits)
    else
      invalid_limits()
    end
  end

  def verify(_compact, _revision, _chain, %Limits{} = limits) do
    if Limits.valid?(limits), do: invalid_type(), else: invalid_limits()
  end

  def verify(_compact, _revision, _chain, _limits), do: invalid_type()

  @doc "Return a termination notice's domain-separated content digest."
  @spec digest(t()) :: binary()
  def digest(%__MODULE__{envelope: %CompactJws{payload_bytes: bytes}}),
    do: :termination_content |> Digest.hash(bytes) |> Digest.to_tagged()

  defp do_verify(compact, supplied_revision, supplied_chain, limits) do
    with {:ok, revision} <- reverify_revision(supplied_revision, limits),
         {:ok, chain} <- reverify_chain(supplied_chain, limits),
         {:ok, termination} <- decode(compact, limits),
         :ok <- claims_match(termination, revision),
         {:ok, descriptor} <- pinned_descriptor(termination, revision, chain),
         {:ok, public_key} <- active_key(descriptor, termination.envelope.kid),
         :ok <- CompactJws.verify_signature(termination.envelope, public_key) do
      {:ok, facts(termination, descriptor)}
    end
  end

  defp decode(compact, limits) do
    with {:ok, envelope} <- CompactJws.parse(compact, "cap+termination", limits),
         {:ok, payload} <- Schema.validate(@definition, envelope.payload) do
      extract(payload, envelope)
    end
  end

  defp extract({:object, members}, envelope) do
    values = Map.new(members)
    {:string, party_role} = values["party_role"]
    {:string, reason_code} = values["reason_code"]
    {:string, effective_at_value} = values["effective_at"]
    {:string, issued_at_value} = values["issued_at"]

    with {:ok, charter_id} <- required_digest(values, "charter_id"),
         {:ok, revision_digest} <- required_digest(values, "governing_revision_digest"),
         {:ok, party_digest} <- required_digest(values, "party_descriptor_digest"),
         {:ok, detail_digest} <- optional_digest(values, "detail_digest"),
         {:ok, effective_at} <- Timestamp.parse(effective_at_value),
         {:ok, issued_at} <- Timestamp.parse(issued_at_value),
         :ok <- issued_before_effective(issued_at, effective_at) do
      {:ok,
       %__MODULE__{
         protocol_revision: 1,
         charter_id: charter_id,
         governing_revision_digest: revision_digest,
         party_descriptor_digest: party_digest,
         party_role: party_role,
         reason_code: reason_code,
         effective_at: effective_at,
         issued_at: issued_at,
         detail_digest: detail_digest,
         envelope: envelope
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp required_digest(values, name) do
    {:string, tagged} = Map.fetch!(values, name)
    valid_digest(tagged)
  end

  defp optional_digest(values, name) do
    case Map.fetch(values, name) do
      :error -> {:ok, nil}
      {:ok, {:string, tagged}} -> valid_digest(tagged)
    end
  end

  defp valid_digest(tagged) do
    case Digest.from_tagged(tagged) do
      {:ok, _digest} -> {:ok, tagged}
      _error -> termination_error()
    end
  end

  defp issued_before_effective(issued_at, effective_at) do
    if Timestamp.compare(issued_at, effective_at) in [:lt, :eq],
      do: :ok,
      else: termination_error()
  end

  defp reverify_revision(%CharterRevision{canonical_bytes: bytes}, limits),
    do: CharterRevision.decode(bytes, limits)

  defp reverify_chain(%DescriptorChain{descriptors: descriptors}, limits) do
    with {:ok, compacts} <- retained_compacts(descriptors),
         true <- compacts != [] do
      DescriptorChain.verify(Enum.uniq(compacts), limits)
    else
      _failure -> chain_error()
    end
  end

  defp retained_compacts(descriptors) when is_list(descriptors) do
    Enum.reduce_while(descriptors, {:ok, []}, fn
      %DescriptorFacts{lineage: lineage}, {:ok, compacts}
      when is_list(lineage) and lineage != [] ->
        if Enum.all?(lineage, &is_binary/1),
          do: {:cont, {:ok, lineage ++ compacts}},
          else: {:halt, chain_error()}

      _facts, _acc ->
        {:halt, chain_error()}
    end)
  end

  defp retained_compacts(_descriptors), do: chain_error()

  defp claims_match(termination, revision) do
    revision_digest = CharterRevision.digest(revision)
    charter_id = revision.charter_id || revision_digest

    if termination.charter_id == charter_id and
         termination.governing_revision_digest == revision_digest and
         termination.reason_code in revision.termination_rules.reason_codes do
      :ok
    else
      claims_error()
    end
  end

  defp pinned_descriptor(termination, revision, chain) do
    party_matches? =
      Enum.any?(revision.parties, fn party ->
        party.role == termination.party_role and
          party.party_descriptor_digest == termination.party_descriptor_digest
      end)

    descriptor =
      Enum.find(chain.descriptors, &(&1.descriptor_digest == termination.party_descriptor_digest))

    if party_matches? and match?(%DescriptorFacts{}, descriptor),
      do: {:ok, descriptor},
      else: claims_error()
  end

  defp active_key(%DescriptorFacts{descriptor: %PartyDescriptor{} = descriptor}, kid) do
    case Enum.find(descriptor.verification_keys, &(&1.key_id == kid and &1.status == :active)) do
      %PartyDescriptor.VerificationKey{public_key: public_key} -> {:ok, public_key}
      nil -> termination_error()
    end
  end

  defp facts(termination, descriptor) do
    {:ok, facts} =
      Facts.build(TerminationFacts, %{
        termination: termination,
        termination_digest: digest(termination),
        charter_id: termination.charter_id,
        governing_revision_digest: termination.governing_revision_digest,
        party_descriptor_digest: termination.party_descriptor_digest,
        party_role: termination.party_role,
        reason_code: termination.reason_code,
        effective_at: termination.effective_at,
        issued_at: termination.issued_at,
        detail_digest: termination.detail_digest,
        signing_key_id: termination.envelope.kid,
        descriptor_position: descriptor.descriptor_position
      })

    facts
  end

  defp termination_error, do: {:error, Error.new(:termination_invalid, ["termination"])}

  defp claims_error,
    do: {:error, Error.new(:termination_claims_mismatch, ["termination", "claims"])}

  defp chain_error,
    do: {:error, Error.new(:descriptor_chain_invalid, ["termination", "descriptor_chain"])}

  defp invalid_limits, do: {:error, Error.new(:invalid_limits, ["limits"])}
  defp invalid_type, do: {:error, Error.new(:invalid_type, ["termination"])}
end
