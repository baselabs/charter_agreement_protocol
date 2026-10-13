defmodule CharterAgreementProtocol.Acceptance do
  @moduledoc """
  CAP never authorizes.

  Decode and verify Acceptances, and detect equivocation. An Acceptance is
  one party's signed assent to one revision.

  Verification proves one party signed exact revision coordinates with a key
  active in the Party Descriptor the claims name. Whether a superseded
  descriptor may still sign, and any legal effect, are your policy; the
  descriptor's position is kept in the facts.

  Most callers use `CharterAgreementProtocol.verify_acceptance/4` or
  `CharterAgreementProtocol.verify_chain/5`, which delegate here.
  """

  alias CharterAgreementProtocol.{
    AcceptanceEquivocation,
    AcceptanceFacts,
    Capability.Profile,
    CharterRevision,
    CompactJws,
    DescriptorChain,
    DescriptorFacts,
    Digest,
    Error,
    Facts,
    Internal.Retained,
    Limits,
    PartyDescriptor,
    Schema,
    Timestamp
  }

  @enforce_keys [
    :protocol_revision,
    :charter_id,
    :revision_number,
    :revision_digest,
    :party_descriptor_digest,
    :party_role,
    :accepted_at,
    :envelope
  ]
  defstruct [
    :protocol_revision,
    :charter_id,
    :revision_number,
    :revision_digest,
    :prev_revision_digest,
    :party_descriptor_digest,
    :party_role,
    :accepted_at,
    :envelope
  ]

  @type t :: %__MODULE__{
          protocol_revision: 1 | 2 | 3,
          charter_id: binary(),
          revision_number: pos_integer(),
          revision_digest: binary(),
          prev_revision_digest: nil | binary(),
          party_descriptor_digest: binary(),
          party_role: binary(),
          accepted_at: Timestamp.t(),
          envelope: CompactJws.t()
        }

  @tagged_digest ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/
  @safe_integer 9_007_199_254_740_991

  @definition Schema.definition("acceptance", [
                Schema.field("protocol_revision",
                  required?: true,
                  types: [:integer],
                  constraint: {:integer_range, 1, 3}
                ),
                Schema.field("charter_id",
                  required?: true,
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                ),
                Schema.field("revision_number",
                  required?: true,
                  types: [:integer],
                  constraint: {:integer_range, 1, @safe_integer}
                ),
                Schema.field("revision_digest",
                  required?: true,
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                ),
                Schema.field("prev_revision_digest",
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
                Schema.field("accepted_at",
                  required?: true,
                  types: [:string],
                  constraint: {:string_bytes, 1, 64}
                )
              ])

  @doc "Verify one Acceptance. See `CharterAgreementProtocol.verify_acceptance/4`."
  @spec verify(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t()) ::
          {:ok, AcceptanceFacts.t()} | {:error, Error.t()}
  @spec verify(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t(), Profile.t()) ::
          {:ok, AcceptanceFacts.t()} | {:error, Error.t()}
  def verify(compact, revision, chain, limits, profile \\ Profile.full())

  def verify(
        compact,
        %CharterRevision{} = supplied_revision,
        %DescriptorChain{} = supplied_chain,
        %Limits{} = limits,
        profile
      ) do
    cond do
      not Limits.valid?(limits) ->
        invalid_limits()

      not Profile.valid?(profile) ->
        {:error, Error.new(:invalid_profile, ["profile"])}

      true ->
        do_verify(compact, supplied_revision, supplied_chain, limits, profile)
    end
  end

  def verify(_compact, _revision, _chain, %Limits{} = limits, profile) do
    cond do
      not Limits.valid?(limits) -> invalid_limits()
      not Profile.valid?(profile) -> {:error, Error.new(:invalid_profile, ["profile"])}
      true -> invalid_type()
    end
  end

  def verify(_compact, _revision, _chain, _limits, _profile), do: invalid_type()

  @doc false
  @spec verify_verified(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t()) ::
          {:ok, AcceptanceFacts.t()} | {:error, Error.t()}
  @spec verify_verified(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t(), Profile.t()) ::
          {:ok, AcceptanceFacts.t()} | {:error, Error.t()}
  def verify_verified(compact, revision, chain, limits, profile \\ Profile.full())

  def verify_verified(
        compact,
        %CharterRevision{} = verified_revision,
        %DescriptorChain{} = verified_chain,
        %Limits{} = limits,
        profile
      ) do
    cond do
      not Limits.valid?(limits) ->
        invalid_limits()

      not Profile.valid?(profile) ->
        {:error, Error.new(:invalid_profile, ["profile"])}

      not Retained.verified_context?(verified_revision, verified_chain) ->
        invalid_type()

      true ->
        with {:ok, prepared} <-
               prepare_verified(compact, verified_revision, verified_chain, limits, profile) do
          verify_prepared(prepared, profile)
        end
    end
  end

  def verify_verified(_compact, _revision, _chain, %Limits{} = limits, profile) do
    cond do
      not Limits.valid?(limits) -> invalid_limits()
      not Profile.valid?(profile) -> {:error, Error.new(:invalid_profile, ["profile"])}
      true -> invalid_type()
    end
  end

  def verify_verified(_compact, _revision, _chain, _limits, _profile), do: invalid_type()

  @doc false
  @spec decode_for_signing(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def decode_for_signing(compact, %Limits{} = limits) when is_binary(compact) do
    if Limits.valid?(limits), do: decode(compact, limits), else: invalid_limits()
  end

  def decode_for_signing(_compact, %Limits{} = limits) do
    if Limits.valid?(limits), do: invalid_type(), else: invalid_limits()
  end

  def decode_for_signing(_compact, _limits), do: invalid_type()

  @doc """
  Return equivocation evidence for two Acceptances by the same signer.

  The two `CharterAgreementProtocol.AcceptanceFacts` must share charter id,
  revision number, descriptor digest and role, and accept different
  revisions. Returns `{:ok, %CharterAgreementProtocol.AcceptanceEquivocation{}}`
  with `winner: nil`, or `:acceptance_equivocation_invalid` otherwise.
  """
  @spec equivocation(term(), term()) ::
          {:ok, AcceptanceEquivocation.t()} | {:error, Error.t()}
  def equivocation(%AcceptanceFacts{} = left, %AcceptanceFacts{} = right) do
    if same_equivocator?(left, right) and left.revision_digest != right.revision_digest do
      {:ok,
       %AcceptanceEquivocation{
         kind: :acceptance_equivocation,
         charter_id: left.charter_id,
         revision_number: left.revision_number,
         party_descriptor_digest: left.party_descriptor_digest,
         party_role: left.party_role,
         acceptance_digests: Enum.sort([left.acceptance_digest, right.acceptance_digest]),
         revision_digests: Enum.sort([left.revision_digest, right.revision_digest]),
         winner: nil
       }}
    else
      equivocation_error()
    end
  end

  def equivocation(_left, _right), do: equivocation_error()

  @doc "Return an Acceptance's domain-separated content digest."
  @spec digest(t()) :: binary()
  def digest(%__MODULE__{envelope: %CompactJws{payload_bytes: bytes}}),
    do: :acceptance_content |> Digest.hash(bytes) |> Digest.to_tagged()

  defp do_verify(compact, supplied_revision, supplied_chain, limits, profile) do
    with {:ok, prepared} <- prepare(compact, supplied_revision, supplied_chain, limits, profile) do
      verify_prepared(prepared, profile)
    end
  end

  @doc false
  @spec prepare(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t(), Profile.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def prepare(compact, supplied_revision, supplied_chain, limits, profile) do
    with {:ok, revision} <- reverify_revision(supplied_revision, limits, profile),
         {:ok, chain} <- reverify_chain(supplied_chain, limits, profile),
         {:ok, prepared} <- prepare_verified(compact, revision, chain, limits, profile) do
      {:ok, Map.put(prepared, :verify_with, {revision, chain})}
    end
  end

  defp prepare_verified(compact, revision, chain, limits, profile) do
    with {:ok, acceptance} <- decode(compact, limits),
         :ok <- claims_match(acceptance, revision),
         {:ok, descriptor} <- pinned_descriptor(acceptance, revision, chain),
         :ok <- CompactJws.admit(acceptance.envelope, profile) do
      {:ok,
       %{
         artifact: acceptance,
         descriptor: descriptor,
         keys: active_keys(descriptor, acceptance.envelope.kid)
       }}
    end
  end

  defp verify_prepared(%{artifact: artifact, descriptor: descriptor, keys: [key]}, profile) do
    with :ok <-
           CompactJws.verify_signature(artifact.envelope, key.public_key, key.algorithm, profile) do
      {:ok, facts(artifact, descriptor)}
    end
  end

  defp verify_prepared(%{keys: []}, _profile), do: acceptance_error()

  defp decode(compact, limits) do
    with {:ok, envelope} <- CompactJws.parse(compact, "cap+acceptance", limits),
         {:ok, payload} <- Schema.validate(@definition, envelope.payload) do
      extract(payload, envelope)
    end
  end

  defp extract({:object, members}, envelope) do
    values = Map.new(members)
    {:integer, revision_number} = values["revision_number"]
    {:integer, protocol_revision} = values["protocol_revision"]
    {:string, party_role} = values["party_role"]
    {:string, accepted_at_value} = values["accepted_at"]

    with {:ok, charter_id} <- required_digest(values, "charter_id"),
         {:ok, revision_digest} <- required_digest(values, "revision_digest"),
         {:ok, previous} <- optional_digest(values, "prev_revision_digest"),
         {:ok, party_digest} <- required_digest(values, "party_descriptor_digest"),
         {:ok, accepted_at} <- Timestamp.parse(accepted_at_value),
         :ok <- coordinate_shape(revision_number, previous) do
      {:ok,
       %__MODULE__{
         protocol_revision: protocol_revision,
         charter_id: charter_id,
         revision_number: revision_number,
         revision_digest: revision_digest,
         prev_revision_digest: previous,
         party_descriptor_digest: party_digest,
         party_role: party_role,
         accepted_at: accepted_at,
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
      _error -> acceptance_error()
    end
  end

  defp coordinate_shape(1, nil), do: :ok
  defp coordinate_shape(number, previous) when number > 1 and is_binary(previous), do: :ok
  defp coordinate_shape(_number, _previous), do: acceptance_error()

  defp reverify_revision(%CharterRevision{canonical_bytes: bytes} = supplied, limits, profile) do
    with {:ok, revision} <- CharterRevision.decode(bytes, limits),
         :ok <- CharterRevision.admit(revision, profile) do
      if Retained.compatible?(supplied, revision), do: {:ok, revision}, else: invalid_type()
    end
  end

  defp reverify_revision(_supplied, _limits, _profile), do: invalid_type()

  defp reverify_chain(%DescriptorChain{descriptors: descriptors} = supplied, limits, profile) do
    with {:ok, compacts} <- retained_compacts(descriptors),
         true <- compacts != [],
         {:ok, chain} <- DescriptorChain.verify(Enum.uniq(compacts), limits, profile),
         true <- Retained.compatible?(supplied, chain) do
      {:ok, chain}
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> chain_error()
    end
  end

  defp reverify_chain(_supplied, _limits, _profile), do: chain_error()

  defp retained_compacts(descriptors) when is_list(descriptors) do
    if Retained.list?(descriptors), do: collect_compacts(descriptors), else: chain_error()
  end

  defp retained_compacts(_descriptors), do: chain_error()

  defp collect_compacts(descriptors) do
    Enum.reduce_while(descriptors, {:ok, []}, fn
      %DescriptorFacts{lineage: lineage}, {:ok, compacts}
      when is_list(lineage) and lineage != [] ->
        if Retained.binaries?(lineage),
          do: {:cont, {:ok, lineage ++ compacts}},
          else: {:halt, chain_error()}

      _facts, _acc ->
        {:halt, chain_error()}
    end)
  end

  defp claims_match(acceptance, revision) do
    revision_digest = CharterRevision.digest(revision)
    charter_id = revision.charter_id || revision_digest

    if acceptance.charter_id == charter_id and
         acceptance.revision_number == revision.revision_number and
         acceptance.revision_digest == revision_digest and
         acceptance.prev_revision_digest == revision.prev_revision_digest do
      :ok
    else
      claims_error()
    end
  end

  defp pinned_descriptor(acceptance, revision, chain) do
    party_matches? =
      Enum.any?(revision.parties, fn party ->
        party.role == acceptance.party_role and
          party.party_descriptor_digest == acceptance.party_descriptor_digest
      end)

    descriptor =
      Enum.find(chain.descriptors, &(&1.descriptor_digest == acceptance.party_descriptor_digest))

    if party_matches? and match?(%DescriptorFacts{}, descriptor),
      do: {:ok, descriptor},
      else: claims_error()
  end

  defp active_keys(%DescriptorFacts{descriptor: %PartyDescriptor{} = descriptor}, kid) do
    Enum.filter(descriptor.verification_keys, &(&1.key_id == kid and &1.status == :active))
  end

  defp facts(acceptance, descriptor) do
    {:ok, facts} =
      Facts.build(AcceptanceFacts, %{
        acceptance: acceptance,
        acceptance_digest: digest(acceptance),
        protocol_revision: acceptance.protocol_revision,
        alg: acceptance.envelope.alg,
        charter_id: acceptance.charter_id,
        revision_number: acceptance.revision_number,
        revision_digest: acceptance.revision_digest,
        prev_revision_digest: acceptance.prev_revision_digest,
        party_descriptor_digest: acceptance.party_descriptor_digest,
        party_role: acceptance.party_role,
        accepted_at: acceptance.accepted_at,
        signing_key_id: acceptance.envelope.kid,
        descriptor_position: descriptor.descriptor_position
      })

    facts
  end

  defp same_equivocator?(left, right) do
    left.charter_id == right.charter_id and
      left.revision_number == right.revision_number and
      left.party_descriptor_digest == right.party_descriptor_digest and
      left.party_role == right.party_role
  end

  defp acceptance_error, do: {:error, Error.new(:acceptance_invalid, ["acceptance"])}

  defp claims_error,
    do: {:error, Error.new(:acceptance_claims_mismatch, ["acceptance", "claims"])}

  defp equivocation_error,
    do: {:error, Error.new(:acceptance_equivocation_invalid, ["acceptance", "equivocation"])}

  defp chain_error,
    do: {:error, Error.new(:descriptor_chain_invalid, ["acceptance", "descriptor_chain"])}

  defp invalid_limits, do: {:error, Error.new(:invalid_limits, ["limits"])}
  defp invalid_type, do: {:error, Error.new(:invalid_type, ["acceptance"])}
end
