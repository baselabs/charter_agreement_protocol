defmodule CharterAgreementProtocol.SigningInput do
  @moduledoc """
  Build the exact bytes a signer signs, and assemble the signed result. CAP
  never authorizes, never holds a key and never signs.

  Callers pass `%{"kid" => kid, "claims" => claims}` with an optional
  `"algorithm"` member: `"Ed25519"` (the default) or `"ML-DSA-65"`. The
  claims' `protocol_revision` must equal that algorithm's emission revision:
  2 for `"Ed25519"` and 3 for `"ML-DSA-65"`. This module builds the closed
  protected header, canonicalizes the claims, checks them with the same
  decoder verification uses, and returns the exact RFC 7515 signing bytes in
  `message`.

  The Acceptance and termination builders also verify the artifact set the
  signer holds and refuse with `:signing_refused` when signing would be
  wrong in that set: an Acceptance with false coordinates, one that
  equivocates, or one whose revision does not descend from every newest
  accepted revision; a termination notice for any revision except the one
  that governs at the notice's own `effective_at`. These checks keep a
  signer from signing something wrong in the set it holds. They cannot stop
  a signer who means to cheat, or prove the set is complete.

  Use `CharterAgreementProtocol.prepare_signing/5` for the holder's
  descriptor key check and explicit limits before external signing.

  Most callers use the functions in `CharterAgreementProtocol`, which
  delegate here. The `charter_agreement_signer` package wraps the whole flow.

  ## Fields

  - `kind`: `:party_descriptor`, `:acceptance`, `:termination` or `:receipt`.
  - `alg`: the JWS `alg` in the protected header.
  - `protected_segment` and `payload_segment`: the base64url header and
    claims segments.
  - `message`: `protected_segment <> "." <> payload_segment`, the bytes to
    sign.
  """

  alias CharterAgreementProtocol.{
    Acceptance,
    Algorithm,
    ArtifactSet,
    Base64Url,
    Canonicalization,
    Chain,
    CharterRevision,
    Error,
    Limits,
    Internal.IntegerClaims,
    PartyDescriptor,
    Receipt,
    TerminationNotice
  }

  @enforce_keys [:kind, :alg, :protected_segment, :payload_segment, :message]
  defstruct @enforce_keys

  @typedoc "The artifact kind a signing input is for."
  @type kind :: :party_descriptor | :acceptance | :termination | :receipt
  @typedoc "The exact bytes to sign for one artifact. See the module doc for each field."
  @type t :: %__MODULE__{
          kind: kind(),
          alg: binary(),
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

  @doc "Build a Party Descriptor signing input. See `CharterAgreementProtocol.descriptor_signing_input/1`."
  @spec descriptor(term()) :: {:ok, t()} | {:error, Error.t()}
  def descriptor(input), do: build_only(:party_descriptor, input)

  @doc "Build a receipt signing input. See `CharterAgreementProtocol.receipt_signing_input/1`."
  @spec receipt(term()) :: {:ok, t()} | {:error, Error.t()}
  def receipt(input), do: build_only(:receipt, input)

  @doc """
  Build an Acceptance signing input after checking it against `set`.
  See `CharterAgreementProtocol.acceptance_signing_input/2`.
  """
  @spec acceptance(term(), ArtifactSet.t()) :: {:ok, t()} | {:error, Error.t()}
  def acceptance(input, %ArtifactSet{} = set) do
    with {:ok, signing_input, acceptance} <- build(:acceptance, input, Limits.default()),
         {:ok, chain} <- verify_set(set),
         {:ok, _revision} <- refusal_check(:acceptance, acceptance, chain) do
      {:ok, signing_input}
    end
  end

  def acceptance(_input, _set), do: invalid()

  @doc """
  Build a termination signing input after checking it against `set`.
  See `CharterAgreementProtocol.termination_signing_input/2`.
  """
  @spec termination(term(), ArtifactSet.t()) :: {:ok, t()} | {:error, Error.t()}
  def termination(input, %ArtifactSet{} = set) do
    with {:ok, signing_input, termination} <- build(:termination, input, Limits.default()),
         {:ok, chain} <- verify_set(set),
         {:ok, _revision} <- refusal_check(:termination, termination, chain) do
      {:ok, signing_input}
    end
  end

  def termination(_input, _set), do: invalid()

  @doc """
  Join a signing input and its raw signature into a compact JWS.

  The signature must be exactly 64 bytes for `"Ed25519"` or 3309 bytes for
  `"ML-DSA-65"`. See `CharterAgreementProtocol.assemble_compact/2`.
  """
  @spec assemble(term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def assemble(input, signature), do: assemble_under(input, signature, Limits.default())

  @doc false
  @spec assemble_under(term(), term(), Limits.t()) :: {:ok, binary()} | {:error, Error.t()}
  def assemble_under(%__MODULE__{} = input, signature, limits) when is_binary(signature) do
    with %{signature_bytes: length} <- Algorithm.row_for(input.alg),
         :ok <- exact_signature_length(signature, length),
         true <- valid_fields?(input),
         compact <- input.message <> "." <> Base64Url.encode(signature),
         {:ok, _artifact} <- decode_kind(input.kind, compact, limits),
         true <- byte_size(compact) <= limits.max_bytes do
      {:ok, compact}
    else
      :signature_length -> signature_invalid()
      _failure -> invalid()
    end
  end

  def assemble_under(_input, _signature, _limits), do: invalid()

  defp exact_signature_length(signature, length) do
    if byte_size(signature) == length, do: :ok, else: :signature_length
  end

  defp build_only(kind, input) do
    case build(kind, input, Limits.default()) do
      {:ok, signing_input, _artifact} -> {:ok, signing_input}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @doc false
  @spec build(kind(), term(), Limits.t()) :: {:ok, t(), struct()} | {:error, Error.t()}
  def build(kind, %{"claims" => claims, "kid" => kid} = input, limits)
      when map_size(input) == 2 and is_map(claims) and is_binary(kid) do
    build(kind, Map.put(input, "algorithm", Algorithm.default_emission_name()), limits)
  end

  def build(kind, %{"claims" => claims, "kid" => kid, "algorithm" => alg} = input, limits)
      when map_size(input) == 3 and is_map(claims) and is_binary(kid) and is_binary(alg) do
    with {:ok, revision} <- emission_revision(alg),
         {:ok, claims_value} <- Canonicalization.from_plain(claims),
         :ok <- IntegerClaims.check(kind, claims_value),
         true <- claims_revision(claims_value, revision),
         {:ok, payload_bytes} <- Canonicalization.encode(claims_value),
         {:ok, protected_bytes} <- protected(kind, kid, alg),
         signing_input <- frame(kind, alg, protected_bytes, payload_bytes),
         true <- valid_fields?(signing_input),
         %{signature_bytes: signature_bytes} <- Algorithm.row_for(alg),
         signature_segment_length <- Kernel.trunc(Float.ceil(signature_bytes * 4 / 3)),
         true <-
           byte_size(signing_input.message) + 1 + signature_segment_length <=
             limits.max_bytes,
         provisional <-
           signing_input.message <> "." <> Base64Url.encode(<<0::size(signature_bytes)-unit(8)>>),
         {:ok, artifact} <- decode_kind(kind, provisional, limits) do
      {:ok, signing_input, artifact}
    else
      _failure -> invalid()
    end
  end

  def build(_kind, _input, _limits), do: invalid()

  # The closed mint set: each emission alg names mints at exactly its emission
  # revision, and the claims must already carry that revision — the
  # provisional decode below re-enforces the full binding rule by construction.
  defp emission_revision(alg) do
    case Map.fetch(Algorithm.emissions(), alg) do
      {:ok, revision} -> {:ok, revision}
      :error -> :error
    end
  end

  defp claims_revision({:object, members}, revision) do
    case List.keyfind(members, "protocol_revision", 0) do
      {"protocol_revision", {:integer, ^revision}} -> true
      _other -> false
    end
  end

  defp protected(kind, kid, alg) do
    with typ when is_binary(typ) <- Map.get(@types, kind),
         true <- Map.has_key?(Algorithm.emissions(), alg),
         true <- valid_kid?(kid) do
      Canonicalization.encode(
        {:object,
         [
           {"alg", {:string, alg}},
           {"kid", {:string, kid}},
           {"typ", {:string, typ}}
         ]}
      )
    else
      _failure -> invalid()
    end
  end

  defp frame(kind, alg, protected_bytes, payload_bytes) do
    protected_segment = Base64Url.encode(protected_bytes)
    payload_segment = Base64Url.encode(payload_bytes)

    %__MODULE__{
      kind: kind,
      alg: alg,
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

  @doc false
  @spec refusal_check(
          :acceptance | :termination,
          struct(),
          CharterAgreementProtocol.ChainFacts.t()
        ) ::
          {:ok, CharterRevision.t()} | {:error, Error.t()}
  def refusal_check(:acceptance, acceptance, chain) do
    with {:ok, revision} <- acceptance_revision(acceptance, chain),
         :ok <- no_equivocation(acceptance, chain),
         :ok <- current_head_in_ancestry(revision, chain),
         do: {:ok, revision}
  end

  def refusal_check(:termination, termination, chain) do
    with {:ok, revision} <- termination_revision(termination, chain),
         :ok <- governing_at_effective_time(termination, revision, chain),
         do: {:ok, revision}
  end

  defp acceptance_revision(acceptance, chain) do
    case Chain.signing_revision(:acceptance, acceptance, chain) do
      {:ok, revision} ->
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

      _missing ->
        refused()
    end
  end

  defp termination_revision(termination, chain) do
    case Chain.signing_revision(:termination, termination, chain) do
      {:ok, revision} ->
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

      _missing ->
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
    revision_index = Chain.revision_index(chain)
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
