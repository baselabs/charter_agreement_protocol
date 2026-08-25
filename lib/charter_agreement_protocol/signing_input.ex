defmodule CharterAgreementProtocol.SigningInput do
  @moduledoc """
  Deterministic attached-JWS framing plus the honest-signer refusal boundary.

  Callers provide exactly `%{"kid" => kid, "claims" => claims}`. This module
  constructs the closed protected header, canonicalizes and validates the
  payload through the existing artifact codec, and returns only the exact RFC
  7515 signing bytes. The set-aware Acceptance producer refuses false
  coordinates, equivocation, and ancestry that excludes any maximum accepted
  head. The set-aware Termination producer refuses every revision except the
  unique governing revision at the notice's own effective time.

  This module never accepts a key, signer, callback, or custody handle and
  never signs. These refusal checks protect honest signers relative to their
  supplied view; they cannot constrain a dishonest signer or prove completeness.
  """

  alias CharterAgreementProtocol.{
    Acceptance,
    ArtifactSet,
    Base64Url,
    Canonicalization,
    Chain,
    CharterRevision,
    Error,
    Limits,
    PartyDescriptor,
    Receipt,
    TerminationNotice
  }

  @enforce_keys [:kind, :protected_segment, :payload_segment, :message]
  defstruct @enforce_keys

  @type kind :: :party_descriptor | :acceptance | :termination | :receipt
  @type t :: %__MODULE__{
          kind: kind(),
          protected_segment: binary(),
          payload_segment: binary(),
          message: binary()
        }

  @types %{
    party_descriptor: "cap+party",
    acceptance: "cap+acceptance",
    termination: "cap+termination",
    receipt: "cap+receipt"
  }

  @doc "Build a canonical Party Descriptor signing input without signing."
  @spec descriptor(term()) :: {:ok, t()} | {:error, Error.t()}
  def descriptor(input), do: build_only(:party_descriptor, input)

  @doc "Build a canonical Receipt signing input without signing."
  @spec receipt(term()) :: {:ok, t()} | {:error, Error.t()}
  def receipt(input), do: build_only(:receipt, input)

  @doc "Build an Acceptance signing input after R1/R2/R3 set refusal checks."
  @spec acceptance(term(), ArtifactSet.t()) :: {:ok, t()} | {:error, Error.t()}
  def acceptance(input, %ArtifactSet{} = set) do
    with {:ok, signing_input, acceptance} <- build(:acceptance, input),
         {:ok, chain} <- verify_set(set),
         {:ok, revision} <- acceptance_revision(acceptance, chain),
         :ok <- no_equivocation(acceptance, chain),
         :ok <- current_head_in_ancestry(revision, chain) do
      {:ok, signing_input}
    end
  end

  def acceptance(_input, _set), do: invalid()

  @doc "Build a Termination signing input after R1/R2/R3 set refusal checks."
  @spec termination(term(), ArtifactSet.t()) :: {:ok, t()} | {:error, Error.t()}
  def termination(input, %ArtifactSet{} = set) do
    with {:ok, signing_input, termination} <- build(:termination, input),
         {:ok, chain} <- verify_set(set),
         {:ok, revision} <- termination_revision(termination, chain),
         :ok <- governing_at_effective_time(termination, revision, chain) do
      {:ok, signing_input}
    end
  end

  def termination(_input, _set), do: invalid()

  @doc "Assemble a validated signing input and exact raw 64-byte signature."
  @spec assemble(term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def assemble(%__MODULE__{} = input, <<_::512>> = signature) do
    compact = input.message <> "." <> Base64Url.encode(signature)

    with true <- valid_fields?(input),
         {:ok, _artifact} <- decode_kind(input.kind, compact, Limits.default()),
         true <- byte_size(compact) <= Limits.default().max_bytes do
      {:ok, compact}
    else
      _failure -> invalid()
    end
  end

  def assemble(%__MODULE__{}, signature) when is_binary(signature), do: signature_invalid()
  def assemble(_input, _signature), do: invalid()

  defp build_only(kind, input) do
    case build(kind, input) do
      {:ok, signing_input, _artifact} -> {:ok, signing_input}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp build(kind, %{"claims" => claims, "kid" => kid} = input)
       when map_size(input) == 2 and is_map(claims) and is_binary(kid) do
    limits = Limits.default()

    with {:ok, claims_value} <- tagged(claims),
         {:ok, payload_bytes} <- Canonicalization.encode(claims_value),
         {:ok, protected_bytes} <- protected(kind, kid),
         signing_input <- frame(kind, protected_bytes, payload_bytes),
         true <- valid_fields?(signing_input),
         true <- byte_size(signing_input.message) + 1 + 86 <= limits.max_bytes,
         provisional <- signing_input.message <> "." <> Base64Url.encode(<<0::512>>),
         {:ok, artifact} <- decode_kind(kind, provisional, limits) do
      {:ok, signing_input, artifact}
    else
      _failure -> invalid()
    end
  end

  defp build(_kind, _input), do: invalid()

  defp protected(kind, kid) do
    with typ when is_binary(typ) <- Map.get(@types, kind),
         true <- valid_kid?(kid) do
      Canonicalization.encode(
        {:object,
         [
           {"alg", {:string, "EdDSA"}},
           {"kid", {:string, kid}},
           {"typ", {:string, typ}}
         ]}
      )
    else
      _failure -> invalid()
    end
  end

  defp frame(kind, protected_bytes, payload_bytes) do
    protected_segment = Base64Url.encode(protected_bytes)
    payload_segment = Base64Url.encode(payload_bytes)

    %__MODULE__{
      kind: kind,
      protected_segment: protected_segment,
      payload_segment: payload_segment,
      message: protected_segment <> "." <> payload_segment
    }
  end

  defp valid_fields?(%__MODULE__{} = input) do
    input.kind in Map.keys(@types) and is_binary(input.protected_segment) and
      input.protected_segment != "" and is_binary(input.payload_segment) and
      input.payload_segment != "" and is_binary(input.message) and
      input.message == input.protected_segment <> "." <> input.payload_segment
  end

  defp decode_kind(:party_descriptor, compact, limits),
    do: PartyDescriptor.decode(compact, limits)

  defp decode_kind(:acceptance, compact, limits),
    do: Acceptance.decode_for_signing(compact, limits)

  defp decode_kind(:termination, compact, limits),
    do: TerminationNotice.decode_for_signing(compact, limits)

  defp decode_kind(:receipt, compact, limits), do: Receipt.decode_for_signing(compact, limits)

  defp verify_set(set) do
    Chain.verify(
      set.revisions,
      set.acceptances,
      set.descriptors,
      set.terminations,
      Limits.default()
    )
  end

  defp acceptance_revision(acceptance, chain) do
    case Enum.find(chain.revision_facts, &(&1.revision_digest == acceptance.revision_digest)) do
      %{revision: revision} ->
        charter_id = revision.charter_id || CharterRevision.digest(revision)

        party_matches? =
          Enum.any?(revision.parties, fn party ->
            party.role == acceptance.party_role and
              party.party_descriptor_digest == acceptance.party_descriptor_digest
          end)

        if acceptance.charter_id == charter_id and
             acceptance.revision_number == revision.revision_number and
             acceptance.prev_revision_digest == revision.prev_revision_digest and party_matches?,
           do: {:ok, revision},
           else: refused()

      nil ->
        refused()
    end
  end

  defp termination_revision(termination, chain) do
    case Enum.find(
           chain.revision_facts,
           &(&1.revision_digest == termination.governing_revision_digest)
         ) do
      %{revision: revision} ->
        charter_id = revision.charter_id || CharterRevision.digest(revision)

        party_matches? =
          Enum.any?(revision.parties, fn party ->
            party.role == termination.party_role and
              party.party_descriptor_digest == termination.party_descriptor_digest
          end)

        if termination.charter_id == charter_id and
             termination.reason_code in revision.termination_rules.reason_codes and party_matches?,
           do: {:ok, revision},
           else: refused()

      nil ->
        refused()
    end
  end

  defp no_equivocation(acceptance, chain) do
    conflict? =
      Enum.any?(chain.acceptance_facts, fn facts ->
        facts.charter_id == acceptance.charter_id and
          facts.revision_number == acceptance.revision_number and
          facts.revision_digest != acceptance.revision_digest
      end)

    if conflict?, do: refused(), else: :ok
  end

  defp governing_at_effective_time(termination, revision, chain) do
    digest = CharterRevision.digest(revision)

    case Chain.governing_revision(chain, termination.effective_at) do
      {:ok, ^digest} -> :ok
      _not_governing -> refused()
    end
  end

  defp current_head_in_ancestry(revision, chain) do
    accepted = Enum.filter(chain.revision_facts, &(&1.acceptance_status == :accepted))
    revision_index = Map.new(chain.revision_facts, &{&1.revision_digest, &1.revision})
    candidate_digest = CharterRevision.digest(revision)

    covered? =
      Enum.all?(accepted_heads(accepted), fn head_digest ->
        head_digest in revision.supersedes or
          ancestor?(candidate_digest, head_digest, revision_index)
      end)

    if covered?, do: :ok, else: refused()
  end

  defp accepted_heads([]), do: []

  defp accepted_heads(facts) do
    maximum = facts |> Enum.map(& &1.revision_number) |> Enum.max()

    facts
    |> Enum.filter(&(&1.revision_number == maximum))
    |> Enum.map(& &1.revision_digest)
  end

  defp ancestor?(digest, digest, _index), do: true

  defp ancestor?(candidate, target, index) do
    case Map.get(index, candidate) do
      %CharterRevision{prev_revision_digest: previous} when is_binary(previous) ->
        ancestor?(previous, target, index)

      _missing_or_root ->
        false
    end
  end

  defp tagged(value) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn
      {name, item}, {:ok, members} when is_binary(name) ->
        case tagged(item) do
          {:ok, tagged_item} -> {:cont, {:ok, [{name, tagged_item} | members]}}
          :error -> {:halt, :error}
        end

      _member, _acc ->
        {:halt, :error}
    end)
    |> case do
      {:ok, members} -> {:ok, {:object, Enum.reverse(members)}}
      :error -> :error
    end
  end

  defp tagged(value) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, items} ->
      case tagged(item) do
        {:ok, tagged_item} -> {:cont, {:ok, [tagged_item | items]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, {:array, Enum.reverse(items)}}
      :error -> :error
    end
  end

  defp tagged(value) when is_binary(value), do: {:ok, {:string, value}}
  defp tagged(value) when is_integer(value), do: {:ok, {:integer, value}}
  defp tagged(value) when is_float(value), do: {:ok, {:float, value}}
  defp tagged(value) when is_boolean(value), do: {:ok, {:boolean, value}}
  defp tagged(nil), do: {:ok, :null}
  defp tagged(_value), do: :error

  defp valid_kid?(kid) when byte_size(kid) in 1..128,
    do: valid_kid_bytes?(kid)

  defp valid_kid?(_kid), do: false
  defp valid_kid_bytes?(<<>>), do: true

  defp valid_kid_bytes?(<<byte, rest::binary>>)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?-, ?., ?_, ?~],
       do: valid_kid_bytes?(rest)

  defp valid_kid_bytes?(_bytes), do: false

  defp invalid, do: {:error, Error.new(:signing_input_invalid, ["signing_input"])}
  defp refused, do: {:error, Error.new(:signing_refused, ["signing_input", "claims"])}

  defp signature_invalid,
    do: {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}
end
