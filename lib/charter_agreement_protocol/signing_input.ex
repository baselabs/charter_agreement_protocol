defmodule CharterAgreementProtocol.SigningInput do
  @moduledoc """
  Build the exact bytes a signer signs, and assemble the signed result. CAP
  never authorizes, never holds a key and never signs.

  Callers pass `%{"kid" => kid, "claims" => claims}` with an optional
  `"algorithm"` member: `"Ed25519"` (the default) or `"ML-DSA-65"`.
  Legacy claims, including receipts, use `protocol_revision` 2 for
  `"Ed25519"` or 3 for `"ML-DSA-65"`. Party descriptors, acceptances
  (including marked assignor acceptances), and termination notices can use
  revision 8 with either algorithm. This module builds the closed protected
  header, canonicalizes the claims, checks them with the verification
  decoder, and returns the exact RFC 7515 signing bytes in `message`.

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

  - `kind`: `:party_descriptor`, `:acceptance`, `:party_replacement`,
    `:termination` or `:receipt`.
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
    Capability.Profile,
    Chain,
    CharterRevision,
    Error,
    Internal.IntegerClaims,
    Internal.SigningScope,
    Limits,
    PartyDescriptor,
    Quorum,
    Receipt,
    TerminationNotice
  }

  @enforce_keys [:kind, :alg, :protected_segment, :payload_segment, :message]
  defstruct @enforce_keys

  @typedoc "The artifact kind a signing input is for."
  @type kind :: :party_descriptor | :acceptance | :party_replacement | :termination | :receipt
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
    party_replacement: "cap+acceptance",
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
  def acceptance(input, set), do: acceptance_input(:acceptance, input, set)

  @doc "Build an assignor's acceptance signing input after checking the declared replacement."
  @spec party_replacement(term(), ArtifactSet.t()) :: {:ok, t()} | {:error, Error.t()}
  def party_replacement(input, set), do: acceptance_input(:party_replacement, input, set)

  defp acceptance_input(kind, input, %ArtifactSet{} = set) do
    with {:ok, signing_input, acceptance} <- build(kind, input, Limits.default()),
         {:ok, chain} <- verify_set(set),
         {:ok, _revision} <- refusal_check(:acceptance, acceptance, chain) do
      {:ok, signing_input}
    end
  end

  defp acceptance_input(_kind, _input, _set), do: invalid()

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
  def assemble_under(%__MODULE__{alg: alg} = input, signature, limits)
      when is_binary(signature) do
    with %{signature_bytes: length} <- Algorithm.row_for(alg),
         :ok <- exact_signature_length(signature, length),
         true <- valid_fields?(input),
         compact <- input.message <> "." <> Base64Url.encode(signature),
         {:ok, _artifact} <- decode_kind(input.kind, compact, limits) do
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
  @spec build(kind(), term(), Limits.t()) ::
          {:ok, t(), struct()} | {:error, Error.t()}
  def build(kind, %{"claims" => claims, "kid" => kid} = input, limits)
      when map_size(input) == 2 and is_map(claims) and is_binary(kid) do
    build(kind, Map.put(input, "algorithm", Algorithm.default_emission_name()), limits)
  end

  def build(operation, %{"claims" => claims, "kid" => kid, "algorithm" => alg} = input, limits)
      when map_size(input) == 3 and is_map(claims) and is_binary(kid) and is_binary(alg) do
    kind = artifact_kind(operation)

    with :ok <- replacement_intent(operation, Map.has_key?(claims, "replacement_role")),
         {:ok, revision} <- emission_revision(alg),
         {:ok, claims_value} <- Canonicalization.from_plain(claims),
         :ok <- IntegerClaims.check(kind, claims_value),
         true <- claims_revision(kind, claims_value, revision),
         {:ok, payload_bytes} <- Canonicalization.encode(claims_value),
         {:ok, protected_bytes} <- protected(operation, kid, alg),
         signing_input = frame(operation, alg, protected_bytes, payload_bytes),
         %{signature_bytes: signature_bytes} <- Algorithm.row_for(alg),
         signature_segment_length <- Kernel.trunc(Float.ceil(signature_bytes * 4 / 3)),
         true <-
           byte_size(signing_input.message) + 1 + signature_segment_length <=
             limits.max_bytes,
         provisional <-
           signing_input.message <> "." <> Base64Url.encode(<<0::size(signature_bytes)-unit(8)>>),
         {:ok, artifact} <- decode_kind(operation, provisional, limits) do
      {:ok, signing_input, artifact}
    else
      {:error, %Error{code: :signing_refused}} = error -> error
      _failure -> invalid()
    end
  end

  def build(_kind, _input, _limits), do: invalid()

  @doc false
  @spec artifact_kind(kind()) :: kind()
  def artifact_kind(:party_replacement), do: :acceptance
  def artifact_kind(kind), do: kind

  defp replacement_intent(:party_replacement, false), do: refused()
  defp replacement_intent(:acceptance, true), do: refused()
  defp replacement_intent(_operation, _marked?), do: :ok

  # The declared emission names stay closed. The provisional decode enforces
  # the artifact-specific revision and protected header binding.
  defp emission_revision(alg) do
    case Map.fetch(Algorithm.emissions(), alg) do
      {:ok, revision} -> {:ok, revision}
      :error -> :error
    end
  end

  defp claims_revision(kind, {:object, members}, revision) do
    case List.keyfind(members, "protocol_revision", 0) do
      {"protocol_revision", {:integer, 8}}
      when kind in [:party_descriptor, :acceptance, :termination] ->
        true

      {"protocol_revision", {:integer, ^revision}} ->
        true

      _other ->
        false
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

  defp valid_fields?(input) do
    kind = Map.get(input, :kind)
    protected = Map.get(input, :protected_segment)
    payload = Map.get(input, :payload_segment)
    message = Map.get(input, :message)

    kind in Map.keys(@types) and is_binary(protected) and protected != "" and
      is_binary(payload) and payload != "" and message == protected <> "." <> payload
  end

  defp decode_kind(:party_descriptor, compact, limits),
    do: PartyDescriptor.decode(compact, limits)

  defp decode_kind(kind, compact, limits) when kind in [:acceptance, :party_replacement] do
    with {:ok, artifact} <- Acceptance.decode_for_signing(compact, limits),
         :ok <- replacement_intent(kind, artifact.replacement_role != nil) do
      {:ok, artifact}
    end
  end

  defp decode_kind(:termination, compact, limits),
    do: TerminationNotice.decode_for_signing(compact, limits)

  defp decode_kind(:receipt, compact, limits), do: Receipt.decode_for_signing(compact, limits)

  defp verify_set(set), do: Chain.verify_set(set, Limits.default(), Profile.full())

  @doc false
  @spec refusal_check(
          :acceptance | :termination,
          struct(),
          CharterAgreementProtocol.ChainFacts.t()
        ) ::
          {:ok, CharterRevision.t()} | {:error, Error.t()}
  def refusal_check(:acceptance, acceptance, chain) do
    with {:ok, revision} <- acceptance_revision(acceptance, chain),
         :ok <-
           SigningScope.refuse(
             SigningScope.in_chains(acceptance, chain.descriptor_chains, "acceptance")
           ),
         :ok <- no_equivocation(acceptance, chain),
         :ok <- current_head_in_ancestry(revision, chain),
         do: {:ok, revision}
  end

  def refusal_check(:termination, termination, chain) do
    with {:ok, revision} <- termination_revision(termination, chain),
         :ok <-
           SigningScope.refuse(
             SigningScope.in_chains(termination, chain.descriptor_chains, "termination")
           ),
         :ok <- governing_at_effective_time(termination, revision, chain),
         do: {:ok, revision}
  end

  defp acceptance_revision(acceptance, chain) do
    case Chain.signing_revision(:acceptance, acceptance, chain) do
      {:ok, revision} -> check_acceptance_revision(acceptance, revision, chain)
      _missing -> refused()
    end
  end

  defp check_acceptance_revision(acceptance, revision, chain) do
    party_matches? = Quorum.accepts_binding?(acceptance, revision)

    cond do
      acceptance.replacement_role != nil and not party_matches? ->
        {:error, Error.new(:acceptance_claims_mismatch, ["acceptance", "claims"])}

      party_matches? and acceptance_eligible?(acceptance, revision, chain) ->
        {:ok, revision}

      true ->
        refused()
    end
  end

  defp acceptance_eligible?(acceptance, revision, chain) do
    charter_id = revision.charter_id || CharterRevision.digest(revision)
    previous = Map.get(Chain.revision_index(chain), revision.prev_revision_digest)
    quorum_acceptance? = acceptance.protocol_revision == 8
    quorum_revision? = revision.protocol_revision == 8

    eligible =
      revision.revision_number == 1 or
        (revision.prev_revision_digest in chain.accepted_revision_digests and
           Enum.all?(revision.supersedes, &(&1 in chain.accepted_revision_digests)))

    quorum_acceptance? == quorum_revision? and
      acceptance.charter_id == charter_id and
      acceptance.revision_number == revision.revision_number and
      acceptance.prev_revision_digest == revision.prev_revision_digest and eligible and
      eligible_role?(acceptance, revision, previous)
  end

  defp eligible_role?(acceptance, revision, previous) do
    (acceptance.replacement_role == nil and revision.party_replacements != []) or
      Quorum.participation_reason(acceptance, revision, previous) == nil
  end

  defp termination_revision(termination, chain) do
    with {:ok, revision} <- Chain.signing_revision(:termination, termination, chain),
         true <- termination_matches?(termination, revision) do
      {:ok, revision}
    else
      _failure -> refused()
    end
  end

  defp termination_matches?(termination, revision) do
    charter_id = revision.charter_id || CharterRevision.digest(revision)
    quorum_termination? = termination.protocol_revision == 8
    quorum_revision? = revision.protocol_revision == 8

    quorum_termination? == quorum_revision? and
      termination.charter_id == charter_id and
      termination.reason_code in revision.termination_rules.reason_codes and
      termination.party_role in Quorum.termination(revision).roles and
      Enum.any?(revision.parties, fn party ->
        party.role == termination.party_role and
          party.party_descriptor_digest == termination.party_descriptor_digest
      end)
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
