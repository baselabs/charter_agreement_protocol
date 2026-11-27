defmodule CharterAgreementProtocol.Receipt do
  @moduledoc """
  CAP never authorizes.

  Closed Receipt codec and view-relative cross-check verifier.

  Chain context re-verifies the retained artifact set, verifies the issuing
  party signature, and compares the claimed revision with governance at the
  caller-authored receipt instant. Revision-only context cannot resolve a
  charter key or governance view. Its facts add `:signature` to `not_verified`
  and report governance as undetermined. A bare revision-8 charter also
  adds `:ownership` to `not_verified`.

  Only revisions that meet their acceptance rules contribute role-to-descriptor
  mappings in chain context. Proposed revision bytes are unauthenticated data
  and cannot promote a counterparty key into another charter role.

  Grant and deployment fields prove exact digest naming only. They never
  establish live authority, execution, or effect truth.
  """

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    ArtifactSet,
    Base64Url,
    Capability.Profile,
    Chain,
    ChainFacts,
    CharterRevision,
    CompactJws,
    DescriptorChain,
    DescriptorFacts,
    Digest,
    Error,
    Extension,
    Facts,
    Internal.Retained,
    Internal.SigningScope,
    Limits,
    ReceiptFacts,
    ReceiptInspection,
    RevisionFacts,
    Schema,
    TerminationFacts,
    Timestamp
  }

  defmodule Grant do
    @moduledoc "An exact, non-authorizing host- or BAP-scheme grant reference carried by a Receipt."
    @enforce_keys [:scheme, :id]
    defstruct [:scheme, :id, :grant_digest]

    @type t :: %__MODULE__{
            scheme: :bap | :host,
            id: binary(),
            grant_digest: nil | binary()
          }
  end

  @enforce_keys [
    :protocol_revision,
    :charter_id,
    :revision_number,
    :revision_digest,
    :issuing_party_role,
    :agent_party_role,
    :deployment_digest,
    :grant,
    :invocation_id,
    :decision,
    :outcome,
    :occurred_at,
    :recorded_at,
    :extensions,
    :extension_outcome,
    :envelope
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          protocol_revision: 1 | 2 | 3,
          charter_id: binary(),
          revision_number: pos_integer(),
          revision_digest: binary(),
          issuing_party_role: binary(),
          agent_party_role: binary(),
          deployment_digest: binary(),
          grant: Grant.t(),
          invocation_id: binary(),
          decision: :accepted | :rejected,
          outcome: :effect_committed | :no_effect | :indeterminate,
          occurred_at: Timestamp.t(),
          recorded_at: Timestamp.t(),
          extensions: CharterAgreementProtocol.Json.value(),
          extension_outcome: Extension.Outcome.t(),
          envelope: CompactJws.t()
        }

  @tagged_digest ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/
  @safe_integer 9_007_199_254_740_991

  @grant_definition Schema.definition("receipt_grant", [
                      Schema.field("scheme",
                        required?: true,
                        types: [:string],
                        constraint: {:one_of, [{:string, "bap"}, {:string, "host"}]}
                      ),
                      Schema.field("id",
                        required?: true,
                        types: [:string],
                        constraint: {:string_bytes, 1, 512}
                      ),
                      Schema.field("grant_digest",
                        types: [:string],
                        constraint: {:matches, @tagged_digest}
                      )
                    ])

  @definition Schema.definition(
                "receipt",
                [
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
                  Schema.field("issuing_party_role",
                    required?: true,
                    types: [:string],
                    constraint: {:string_bytes, 1, 128}
                  ),
                  Schema.field("agent_party_role",
                    required?: true,
                    types: [:string],
                    constraint: {:string_bytes, 1, 128}
                  ),
                  Schema.field("deployment_digest",
                    required?: true,
                    types: [:string],
                    constraint: {:matches, @tagged_digest}
                  ),
                  Schema.field("grant",
                    required?: true,
                    types: [:object],
                    nested: {:object, @grant_definition}
                  ),
                  Schema.field("invocation_id",
                    required?: true,
                    types: [:string],
                    constraint: {:string_bytes, 1, 512}
                  ),
                  Schema.field("decision",
                    required?: true,
                    types: [:string],
                    constraint: {:one_of, [{:string, "accepted"}, {:string, "rejected"}]}
                  ),
                  Schema.field("outcome",
                    required?: true,
                    types: [:string],
                    constraint:
                      {:one_of,
                       [
                         {:string, "effect_committed"},
                         {:string, "no_effect"},
                         {:string, "indeterminate"}
                       ]}
                  ),
                  Schema.field("occurred_at",
                    required?: true,
                    types: [:string],
                    constraint: {:string_bytes, 1, 64}
                  ),
                  Schema.field("recorded_at",
                    required?: true,
                    types: [:string],
                    constraint: {:string_bytes, 1, 64}
                  ),
                  Schema.field("extensions", required?: true, types: [:object])
                ],
                cross_field: [
                  {:allowed, ["decision", "outcome"],
                   [
                     [{:string, "accepted"}, {:string, "effect_committed"}],
                     [{:string, "accepted"}, {:string, "no_effect"}],
                     [{:string, "accepted"}, {:string, "indeterminate"}],
                     [{:string, "rejected"}, {:string, "no_effect"}]
                   ]}
                ]
              )

  @doc "Verify one attached receipt against revision-only or full-chain context."
  @spec verify(term(), ChainFacts.t() | CharterRevision.t(), Limits.t()) ::
          {:ok, ReceiptFacts.t()} | {:error, Error.t()}
  @spec verify(term(), ChainFacts.t() | CharterRevision.t(), Limits.t(), Profile.t()) ::
          {:ok, ReceiptFacts.t()} | {:error, Error.t()}
  def verify(compact, context, limits, profile \\ Profile.full())

  def verify(compact, context, %Limits{} = limits, profile)
      when is_struct(context, ChainFacts) or is_struct(context, CharterRevision) do
    cond do
      not Limits.valid?(limits) -> invalid_limits()
      not Profile.valid?(profile) -> {:error, Error.new(:invalid_profile, ["profile"])}
      true -> do_verify(compact, context, limits, profile)
    end
  end

  def verify(_compact, _context, %Limits{} = limits, profile) do
    cond do
      not Limits.valid?(limits) -> invalid_limits()
      not Profile.valid?(profile) -> {:error, Error.new(:invalid_profile, ["profile"])}
      true -> invalid_type()
    end
  end

  def verify(_compact, _context, _limits, _profile), do: invalid_type()

  @doc "Inspect a receipt against raw retained chain artifacts and an optional grant digest."
  @spec inspect(term(), ArtifactSet.t(), binary() | nil, Limits.t(), Profile.t()) ::
          {:ok, ReceiptInspection.t()} | {:error, Error.t()}
  def inspect(compact, artifact_set, grant_reference, limits, profile) do
    with :ok <- Limits.check(limits),
         :ok <- Profile.check(profile),
         :ok <- check_grant_reference(grant_reference),
         {:ok, chain} <- Chain.verify_set(artifact_set, limits, profile),
         {:ok, prepared} <- prepare_verified_receipt(compact, {:chain, chain}, limits, profile),
         {:ok, {public, algorithm}} <- verify_prepared_signature(prepared, profile) do
      key = %{
        "algorithm" => algorithm,
        "key_id" => prepared.artifact.envelope.kid,
        "public_key" => Base64Url.encode(public),
        "status" => "active"
      }

      ReceiptInspection.build(
        compact,
        prepared.artifact,
        chain,
        key,
        prepared.projection.deployment_digest_matched,
        prepared.scope.scope_status,
        grant_reference
      )
    end
  end

  defp check_grant_reference(nil), do: :ok

  defp check_grant_reference(reference) when is_binary(reference) do
    if byte_size(reference) == 51 and match?({:ok, _digest}, Digest.from_tagged(reference)),
      do: :ok,
      else: {:error, Error.new(:digest_encoding_invalid, ["grant_reference"])}
  end

  defp check_grant_reference(_reference), do: invalid_type()

  @doc false
  @spec decode_for_signing(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def decode_for_signing(compact, %Limits{} = limits) when is_binary(compact) do
    if Limits.valid?(limits), do: decode(compact, limits), else: invalid_limits()
  end

  def decode_for_signing(_compact, %Limits{} = limits) do
    if Limits.valid?(limits), do: invalid_type(), else: invalid_limits()
  end

  def decode_for_signing(_compact, _limits), do: invalid_type()

  @doc "Return a Receipt's domain-separated content digest."
  @spec digest(t()) :: binary()
  def digest(%__MODULE__{envelope: %CompactJws{payload_bytes: bytes}}),
    do: :receipt_content |> Digest.hash(bytes) |> Digest.to_tagged()

  defp do_verify(compact, context, limits, profile) do
    with {:ok, prepared} <- prepare_receipt(compact, context, limits, profile),
         {:ok, _key} <- verify_prepared_signature(prepared, profile) do
      facts(prepared.artifact, prepared.projection, prepared.context, prepared.scope)
    end
  end

  @doc false
  @spec prepare(term(), ChainFacts.t() | CharterRevision.t(), Limits.t(), Profile.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def prepare(compact, context, limits, profile) do
    with {:ok, prepared} <- prepare_receipt(compact, context, limits, profile) do
      prepare_context(prepared)
    end
  end

  defp prepare_context(%{context: {:revision, %CharterRevision{protocol_revision: 8}}}),
    do: {:error, Error.new(:signing_refused, ["signing_input", "context"])}

  defp prepare_context(prepared) do
    if prepared.keys not in [:unnamed, []] and prepared.holder_keys == [],
      do: claims_error(),
      else: {:ok, %{prepared | keys: prepared.holder_keys}}
  end

  defp prepare_receipt(compact, context, limits, profile) do
    with {:ok, context} <- reverify_context(context, limits, profile) do
      prepare_verified_receipt(compact, context, limits, profile)
    end
  end

  defp prepare_verified_receipt(compact, verified_context, limits, profile) do
    with {:ok, receipt} <- decode(compact, limits),
         {:ok, projection} <- project(receipt, verified_context),
         :ok <- CompactJws.admit(receipt.envelope, profile) do
      {keys, holder_keys, holder_match, scope} = context_keys(verified_context, receipt)

      {:ok,
       %{
         artifact: receipt,
         projection: Map.put(projection, :holder_match, holder_match),
         context: verified_context,
         verify_with: elem(verified_context, 1),
         keys: keys,
         holder_keys: holder_keys,
         scope: scope
       }}
    end
  end

  defp context_keys({:revision, _revision}, _receipt),
    do: {:unnamed, :unnamed, :not_evaluated, SigningScope.unverified()}

  defp context_keys({:chain, chain}, receipt) do
    accepted = Enum.filter(chain.revision_facts, &(&1.acceptance_status == :accepted))

    recognized = Enum.find(accepted, &(&1.revision_digest == receipt.revision_digest))
    revisions = if recognized, do: [recognized], else: accepted

    descriptors = Enum.flat_map(chain.descriptor_chains, & &1.descriptors)
    role = receipt.issuing_party_role
    digests = MapSet.new(revisions, &role_digest(&1.revision, role))
    claimed = Enum.filter(descriptors, &MapSet.member?(digests, &1.descriptor_digest))
    {holder_match, holder} = receipt_holder(chain, accepted, receipt, descriptors)
    keys = descriptor_keys(claimed, receipt.envelope.kid)
    held = Enum.filter(claimed, &(&1.party_id == holder))
    holder_keys = if holder, do: descriptor_keys(held, receipt.envelope.kid), else: keys
    scope = receipt_scope(recognized, claimed, receipt.envelope.kid, role)
    {keys, holder_keys, holder_match, scope}
  end

  defp receipt_scope(nil, _descriptors, _kid, _role), do: SigningScope.unverified()

  defp receipt_scope(_revision, [%DescriptorFacts{descriptor: descriptor}], kid, role),
    do: SigningScope.for_key(descriptor, kid, role, "receipt")

  defp verify_prepared_signature(%{keys: :unnamed}, _profile), do: {:ok, nil}

  defp verify_prepared_signature(
         %{artifact: receipt, keys: keys, holder_keys: holders},
         profile
       ) do
    results =
      Enum.map(keys, fn {public_key, algorithm} ->
        CompactJws.verify_signature(receipt.envelope, public_key, algorithm, profile)
      end)

    with :ok <- signature_outcome(results) do
      case Enum.find(Enum.zip(keys, results), &holder_signature?(&1, holders)) do
        {key, :ok} -> {:ok, key}
        nil -> claims_error()
      end
    end
  end

  defp holder_signature?({key, status}, holders), do: status == :ok and key in holders

  defp decode(compact, limits) do
    with {:ok, envelope} <- CompactJws.parse(compact, "cap+receipt", limits),
         {:ok, payload} <- Schema.validate(@definition, envelope.payload) do
      extract(payload, envelope)
    end
  end

  defp extract({:object, members}, envelope) do
    values = Map.new(members)
    {:integer, revision_number} = values["revision_number"]
    {:string, issuing_role} = values["issuing_party_role"]
    {:string, agent_role} = values["agent_party_role"]
    {:string, invocation_id} = values["invocation_id"]
    {:integer, protocol_revision} = values["protocol_revision"]
    {:string, decision_value} = values["decision"]
    {:string, outcome_value} = values["outcome"]
    {:string, occurred_value} = values["occurred_at"]
    {:string, recorded_value} = values["recorded_at"]

    with {:ok, charter_id} <- required_digest(values, "charter_id"),
         {:ok, revision_digest} <- required_digest(values, "revision_digest"),
         {:ok, deployment_digest} <- required_digest(values, "deployment_digest"),
         {:ok, grant} <- extract_grant(values["grant"]),
         {:ok, extension_outcome} <- Extension.validate(values["extensions"], :receipt),
         {:ok, occurred_at} <- Timestamp.parse(occurred_value),
         {:ok, recorded_at} <- Timestamp.parse(recorded_value),
         :ok <- recorded_after_occurred(occurred_at, recorded_at) do
      {:ok,
       %__MODULE__{
         protocol_revision: protocol_revision,
         charter_id: charter_id,
         revision_number: revision_number,
         revision_digest: revision_digest,
         issuing_party_role: issuing_role,
         agent_party_role: agent_role,
         deployment_digest: deployment_digest,
         grant: grant,
         invocation_id: invocation_id,
         decision: decision(decision_value),
         outcome: outcome(outcome_value),
         occurred_at: occurred_at,
         recorded_at: recorded_at,
         extensions: values["extensions"],
         extension_outcome: extension_outcome,
         envelope: envelope
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp extract_grant({:object, members}) do
    values = Map.new(members)
    {:string, scheme_value} = values["scheme"]
    {:string, id} = values["id"]

    with {:ok, grant_digest} <- optional_digest(values, "grant_digest"),
         :ok <- required_bap_digest(scheme_value, grant_digest) do
      {:ok, %Grant{scheme: grant_scheme(scheme_value), id: id, grant_digest: grant_digest}}
    end
  end

  defp required_digest(values, name) do
    {:string, tagged} = Map.fetch!(values, name)

    case Digest.from_tagged(tagged) do
      {:ok, _digest} -> {:ok, tagged}
      _error -> receipt_error()
    end
  end

  defp optional_digest(values, name) do
    case Map.fetch(values, name) do
      :error -> {:ok, nil}
      {:ok, {:string, tagged}} -> required_digest(%{name => {:string, tagged}}, name)
    end
  end

  defp required_bap_digest("bap", digest) when is_binary(digest), do: :ok
  defp required_bap_digest("host", _digest), do: :ok
  defp required_bap_digest(_scheme, _digest), do: receipt_error()

  defp recorded_after_occurred(occurred_at, recorded_at) do
    if Timestamp.compare(recorded_at, occurred_at) in [:eq, :gt], do: :ok, else: receipt_error()
  end

  defp reverify_context(%CharterRevision{canonical_bytes: bytes} = supplied, limits, profile) do
    with {:ok, revision} <- CharterRevision.decode(bytes, limits),
         :ok <- CharterRevision.admit(revision, profile) do
      if Retained.compatible?(supplied, revision),
        do: {:ok, {:revision, revision}},
        else: invalid_type()
    end
  end

  defp reverify_context(%ChainFacts{} = facts, limits, profile) do
    with {:ok, revisions} <- retained_revisions(facts),
         {:ok, acceptances} <- retained_acceptances(facts),
         {:ok, descriptors} <- retained_descriptors(facts),
         {:ok, terminations} <- retained_terminations(facts),
         {:ok, verified} <-
           Chain.verify(revisions, acceptances, descriptors, terminations, limits, profile) do
      if Retained.compatible?(facts, verified),
        do: {:ok, {:chain, verified}},
        else: invalid_type()
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp reverify_context(_supplied, _limits, _profile), do: invalid_type()

  defp retained_revisions(%ChainFacts{revision_facts: facts}) when is_list(facts) do
    collect_retained(facts, fn
      %RevisionFacts{revision: %CharterRevision{canonical_bytes: bytes}} when is_binary(bytes) ->
        {:ok, bytes}

      _facts ->
        :error
    end)
  end

  defp retained_revisions(_facts), do: invalid_type()

  defp retained_acceptances(%ChainFacts{acceptance_facts: facts}) when is_list(facts),
    do: collect_retained(facts, &acceptance_compact/1)

  defp retained_acceptances(_facts), do: invalid_type()

  defp acceptance_compact(%AcceptanceFacts{acceptance: %{envelope: %CompactJws{} = envelope}}),
    do: Retained.compact(envelope)

  defp acceptance_compact(_facts), do: :error

  defp retained_descriptors(%ChainFacts{descriptor_chains: chains}) when is_list(chains) do
    with true <- Retained.list?(chains),
         {:ok, groups} <- collect_retained(chains, &descriptor_compacts/1) do
      compacts = groups |> List.flatten() |> Enum.uniq()
      if compacts != [], do: {:ok, compacts}, else: invalid_type()
    else
      _failure -> invalid_type()
    end
  end

  defp retained_descriptors(_facts), do: invalid_type()

  defp descriptor_compacts(%DescriptorChain{descriptors: descriptors}) do
    with true <- Retained.list?(descriptors),
         {:ok, groups} <- collect_retained(descriptors, &descriptor_lineage/1) do
      {:ok, List.flatten(groups)}
    else
      _failure -> :error
    end
  end

  defp descriptor_compacts(_other), do: :error

  defp descriptor_lineage(%DescriptorFacts{lineage: lineage}) do
    if Retained.binaries?(lineage),
      do: {:ok, lineage},
      else: :error
  end

  defp descriptor_lineage(_other), do: :error

  defp retained_terminations(%ChainFacts{termination_facts: facts}) when is_list(facts),
    do: collect_retained(facts, &termination_compact/1)

  defp retained_terminations(_facts), do: invalid_type()

  defp termination_compact(%TerminationFacts{termination: %{envelope: %CompactJws{} = envelope}}),
    do: Retained.compact(envelope)

  defp termination_compact(_facts), do: :error

  defp collect_retained(items, function) do
    if Retained.list?(items), do: collect_items(items, function), else: invalid_type()
  end

  defp collect_items(items, function) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, values} ->
      case function.(item) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        _failure -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> invalid_type()
    end
  end

  defp project(receipt, {:revision, revision}) do
    with :ok <- recognized_claims(receipt, revision) do
      {:ok,
       %{chain_conflict: :none, governing_match: :undetermined, deployment_digest_matched: true}}
    end
  end

  defp project(receipt, {:chain, chain}) do
    case Enum.find(
           chain.revision_facts,
           &(&1.acceptance_status == :accepted and
               &1.revision_digest == receipt.revision_digest)
         ) do
      %RevisionFacts{revision: revision} ->
        with :ok <- recognized_claims(receipt, revision) do
          {:ok,
           %{
             chain_conflict: :none,
             governing_match: governing_match(chain, receipt),
             deployment_digest_matched: true
           }}
        end

      nil ->
        unknown_projection(receipt, chain)
    end
  end

  defp recognized_claims(receipt, revision) do
    revision_digest = CharterRevision.digest(revision)
    charter_id = revision.charter_id || revision_digest

    roles = MapSet.new(revision.parties, & &1.role)

    deployment_matches? =
      Enum.any?(revision.abp_bindings, fn binding ->
        binding.party_role == receipt.agent_party_role and
          binding.deployment_digest == receipt.deployment_digest
      end)

    if receipt.charter_id == charter_id and receipt.revision_digest == revision_digest and
         receipt.revision_number == revision.revision_number and
         MapSet.member?(roles, receipt.issuing_party_role) and
         MapSet.member?(roles, receipt.agent_party_role) and deployment_matches? do
      :ok
    else
      claims_error()
    end
  end

  defp unknown_projection(receipt, chain) do
    accepted = Enum.filter(chain.revision_facts, &(&1.acceptance_status == :accepted))
    accepted_head = accepted |> Enum.map(& &1.revision_number) |> Enum.max(fn -> 0 end)
    roles = chain_roles(chain)

    if receipt.charter_id == chain.charter_id and
         MapSet.member?(roles, receipt.issuing_party_role) and
         MapSet.member?(roles, receipt.agent_party_role) do
      conflict = if receipt.revision_number <= accepted_head, do: :fork_evidenced, else: :none

      {:ok,
       %{
         chain_conflict: conflict,
         governing_match: governing_match(chain, receipt),
         deployment_digest_matched: false
       }}
    else
      claims_error()
    end
  end

  defp chain_roles(chain) do
    chain.revision_facts
    |> Enum.filter(&(&1.acceptance_status == :accepted))
    |> Enum.flat_map(& &1.revision.parties)
    |> MapSet.new(& &1.role)
  end

  defp governing_match(chain, receipt) do
    case Chain.governing_revision(chain, receipt.occurred_at) do
      {:ok, digest} when digest == receipt.revision_digest -> :match
      {:ok, :contested} -> :undetermined
      {:ok, _other} -> :mismatch
    end
  end

  @doc false
  @spec signature_outcome([:ok | {:error, Error.t()}]) :: :ok | {:error, Error.t()}
  def signature_outcome(results) do
    case Enum.count(results, &(&1 == :ok)) do
      1 ->
        :ok

      0 ->
        # An honest failure (substrate obstacle or profile rejection) is
        # reported verbatim when no candidate verified: a deterministic
        # policy rejection must never wear a forgery verdict.
        case Enum.find(results, &honest_failure?/1) do
          {:error, %Error{code: :algorithm_unsupported_on_substrate}} ->
            {:error, Error.new(:algorithm_unsupported_on_substrate, ["compact_jws", "signature"])}

          {:error, %Error{code: :algorithm_outside_profile}} ->
            {:error, Error.new(:algorithm_outside_profile, ["compact_jws", "alg"])}

          {:error, %Error{code: :revision_outside_profile}} ->
            {:error, Error.new(:revision_outside_profile, ["compact_jws", "protocol_revision"])}

          _none ->
            {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}
        end

      _ambiguous ->
        {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}
    end
  end

  defp honest_failure?({:error, %Error{code: :algorithm_unsupported_on_substrate}}), do: true
  defp honest_failure?({:error, %Error{code: :algorithm_outside_profile}}), do: true
  defp honest_failure?({:error, %Error{code: :revision_outside_profile}}), do: true
  defp honest_failure?(_other), do: false

  defp descriptor_keys(descriptors, kid) do
    descriptors
    |> Enum.flat_map(fn facts ->
      for key <- facts.descriptor.verification_keys,
          key.key_id == kid and key.status == :active,
          do: {key.public_key, key.algorithm}
    end)
    |> Enum.uniq()
  end

  defp role_digest(revision, role) do
    Enum.find_value(revision.parties, fn binding ->
      if binding.role == role, do: binding.party_descriptor_digest
    end)
  end

  defp receipt_holder(chain, accepted, receipt, descriptors) do
    if Enum.any?(accepted, &(&1.revision.party_replacements != [])) do
      {status, digest} = holder_revision(chain, receipt)
      held = Enum.find(accepted, &(&1.revision_digest == digest))
      descriptor = held && role_digest(held.revision, receipt.issuing_party_role)

      holder = Enum.find(descriptors, &(&1.descriptor_digest == descriptor))
      owner = holder && holder.party_id

      {if(owner, do: status, else: :undetermined), owner}
    else
      {:not_evaluated, nil}
    end
  end

  defp holder_revision(chain, receipt) do
    case Chain.governing_revision(chain, receipt.occurred_at) do
      {:ok, digest} when is_binary(digest) ->
        {:match, digest}

      {:ok, :none} ->
        digest =
          Chain.latest_assignment_revision(chain, receipt.issuing_party_role, receipt.occurred_at)

        {:undetermined, digest}

      {:ok, :contested} ->
        {:undetermined, nil}
    end
  end

  defp facts(receipt, projection, verified_context, scope) do
    additions =
      case verified_context do
        {:revision, %CharterRevision{protocol_revision: 8}} -> [:signature, :ownership]
        {:revision, _legacy} -> [:signature]
        {:chain, _chain} -> []
      end

    signing_key_id = if additions == [], do: receipt.envelope.kid, else: nil

    Facts.build(
      ReceiptFacts,
      %{
        receipt_digest: digest(receipt),
        protocol_revision: receipt.protocol_revision,
        alg: receipt.envelope.alg,
        charter_id: receipt.charter_id,
        revision_number: receipt.revision_number,
        revision_digest: receipt.revision_digest,
        issuing_party_role: receipt.issuing_party_role,
        agent_party_role: receipt.agent_party_role,
        deployment_digest: receipt.deployment_digest,
        grant_scheme: receipt.grant.scheme,
        grant_digest: receipt.grant.grant_digest,
        invocation_id: receipt.invocation_id,
        decision: receipt.decision,
        outcome: receipt.outcome,
        occurred_at: receipt.occurred_at,
        recorded_at: receipt.recorded_at,
        signing_key_id: signing_key_id,
        scope_status: scope.scope_status,
        signer_thumbprint: scope.signer_thumbprint,
        chain_conflict: projection.chain_conflict,
        governing_match: projection.governing_match,
        holder_match: projection.holder_match,
        deployment_digest_matched: projection.deployment_digest_matched,
        optional_extensions_retained: receipt.extension_outcome.optional_retained
      },
      additions
    )
  end

  defp decision("accepted"), do: :accepted
  defp decision("rejected"), do: :rejected
  defp outcome("effect_committed"), do: :effect_committed
  defp outcome("no_effect"), do: :no_effect
  defp outcome("indeterminate"), do: :indeterminate
  defp grant_scheme("bap"), do: :bap
  defp grant_scheme("host"), do: :host

  defp receipt_error, do: {:error, Error.new(:receipt_invalid, ["receipt"])}

  defp claims_error,
    do: {:error, Error.new(:receipt_claims_mismatch, ["receipt", "claims"])}

  defp invalid_limits, do: {:error, Error.new(:invalid_limits, ["limits"])}
  defp invalid_type, do: {:error, Error.new(:invalid_type, ["receipt"])}
end
