defmodule CharterAgreementProtocol.Receipt do
  @moduledoc """
  Closed Receipt codec and view-relative cross-check verifier.

  Chain context re-verifies the retained artifact set, verifies the issuing
  party signature, and compares the claimed revision with governance at the
  caller-authored receipt instant. Revision-only context cannot resolve a
  charter key or governance view; its facts add `:signature` to `not_verified`
  and report governance as undetermined.

  Only bilaterally accepted revision facts contribute role-to-descriptor
  mappings in chain context. Proposed revision bytes are unauthenticated data
  and cannot promote a counterparty key into another charter role.

  Grant and deployment fields prove exact digest naming only. They never
  establish live authority, execution, or effect truth.
  """

  alias CharterAgreementProtocol.{
    AcceptanceFacts,
    Base64Url,
    Chain,
    ChainFacts,
    CharterRevision,
    CompactJws,
    DescriptorChain,
    DescriptorFacts,
    Digest,
    Error,
    Facts,
    Limits,
    ReceiptFacts,
    RevisionFacts,
    Schema,
    TerminationFacts,
    Timestamp
  }

  defmodule Grant do
    @moduledoc "An exact host- or BAP-scheme grant reference carried by a Receipt."
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
    :envelope
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          protocol_revision: 1,
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
                    constraint: {:integer_range, 1, 1}
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
                  Schema.field("occurred_at", required?: true, types: [:string]),
                  Schema.field("recorded_at", required?: true, types: [:string]),
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
  def verify(compact, context, %Limits{} = limits)
      when is_struct(context, ChainFacts) or is_struct(context, CharterRevision) do
    if Limits.valid?(limits), do: do_verify(compact, context, limits), else: invalid_limits()
  end

  def verify(_compact, _context, %Limits{} = limits) do
    if Limits.valid?(limits), do: invalid_type(), else: invalid_limits()
  end

  def verify(_compact, _context, _limits), do: invalid_type()

  @doc "Return a Receipt's domain-separated content digest."
  @spec digest(t()) :: binary()
  def digest(%__MODULE__{envelope: %CompactJws{payload_bytes: bytes}}),
    do: :receipt_content |> Digest.hash(bytes) |> Digest.to_tagged()

  defp do_verify(compact, context, limits) do
    with {:ok, verified_context} <- reverify_context(context, limits),
         {:ok, receipt} <- decode(compact, limits),
         {:ok, projection} <- project(receipt, verified_context),
         :ok <- verify_context_signature(receipt, verified_context) do
      facts(receipt, projection, verified_context)
    end
  end

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
    {:string, decision_value} = values["decision"]
    {:string, outcome_value} = values["outcome"]
    {:string, occurred_value} = values["occurred_at"]
    {:string, recorded_value} = values["recorded_at"]

    with {:ok, charter_id} <- required_digest(values, "charter_id"),
         {:ok, revision_digest} <- required_digest(values, "revision_digest"),
         {:ok, deployment_digest} <- required_digest(values, "deployment_digest"),
         {:ok, grant} <- extract_grant(values["grant"]),
         {:ok, occurred_at} <- Timestamp.parse(occurred_value),
         {:ok, recorded_at} <- Timestamp.parse(recorded_value),
         :ok <- recorded_after_occurred(occurred_at, recorded_at) do
      {:ok,
       %__MODULE__{
         protocol_revision: 1,
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

  defp reverify_context(%CharterRevision{canonical_bytes: bytes}, limits) do
    case CharterRevision.decode(bytes, limits) do
      {:ok, revision} -> {:ok, {:revision, revision}}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp reverify_context(%ChainFacts{} = facts, limits) do
    with {:ok, revisions} <- retained_revisions(facts),
         {:ok, acceptances} <- retained_acceptances(facts),
         {:ok, descriptors} <- retained_descriptors(facts),
         {:ok, terminations} <- retained_terminations(facts),
         {:ok, verified} <-
           Chain.verify(revisions, acceptances, descriptors, terminations, limits) do
      {:ok, {:chain, verified}}
    else
      {:error, %Error{} = error} -> {:error, error}
      _failure -> receipt_error()
    end
  end

  defp retained_revisions(%ChainFacts{revision_facts: facts}) when is_list(facts) do
    collect_retained(facts, fn
      %RevisionFacts{revision: %CharterRevision{canonical_bytes: bytes}} when is_binary(bytes) ->
        {:ok, bytes}

      _facts ->
        :error
    end)
  end

  defp retained_revisions(_facts), do: receipt_error()

  defp retained_acceptances(%ChainFacts{acceptance_facts: facts}) when is_list(facts),
    do: collect_retained(facts, &acceptance_compact/1)

  defp retained_acceptances(_facts), do: receipt_error()

  defp acceptance_compact(%AcceptanceFacts{acceptance: %{envelope: %CompactJws{} = envelope}}),
    do: {:ok, envelope_compact(envelope)}

  defp acceptance_compact(_facts), do: :error

  defp retained_descriptors(%ChainFacts{descriptor_chains: chains}) when is_list(chains) do
    compacts =
      Enum.flat_map(chains, fn
        %DescriptorChain{descriptors: descriptors} when is_list(descriptors) ->
          Enum.flat_map(descriptors, fn
            %DescriptorFacts{lineage: lineage} when is_list(lineage) -> lineage
            _facts -> []
          end)

        _chain ->
          []
      end)
      |> Enum.uniq()

    if compacts != [] and Enum.all?(compacts, &is_binary/1), do: {:ok, compacts}, else: :error
  end

  defp retained_descriptors(_facts), do: receipt_error()

  defp retained_terminations(%ChainFacts{termination_facts: facts}) when is_list(facts),
    do: collect_retained(facts, &termination_compact/1)

  defp retained_terminations(_facts), do: receipt_error()

  defp termination_compact(%TerminationFacts{termination: %{envelope: %CompactJws{} = envelope}}),
    do: {:ok, envelope_compact(envelope)}

  defp termination_compact(_facts), do: :error

  defp collect_retained(items, function) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, values} ->
      case function.(item) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> receipt_error()
    end
  end

  defp envelope_compact(envelope),
    do: envelope.message <> "." <> Base64Url.encode(envelope.signature)

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

  defp verify_context_signature(_receipt, {:revision, %CharterRevision{}}), do: :ok

  defp verify_context_signature(receipt, {:chain, chain}) do
    verified_keys =
      chain
      |> signing_keys(receipt)
      |> Enum.uniq()
      |> Enum.filter(&(CompactJws.verify_signature(receipt.envelope, &1) == :ok))

    if length(verified_keys) == 1,
      do: :ok,
      else: {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}
  end

  defp signing_keys(chain, receipt) do
    recognized_revision? =
      Enum.any?(
        chain.revision_facts,
        &(&1.acceptance_status == :accepted and
            &1.revision_digest == receipt.revision_digest)
      )

    descriptor_digests =
      chain.revision_facts
      |> Enum.filter(fn facts ->
        facts.acceptance_status == :accepted and
          (facts.revision_digest == receipt.revision_digest or not recognized_revision?)
      end)
      |> Enum.flat_map(fn facts ->
        facts.revision.parties
        |> Enum.filter(&(&1.role == receipt.issuing_party_role))
        |> Enum.map(& &1.party_descriptor_digest)
      end)
      |> Enum.uniq()

    chain.descriptor_chains
    |> Enum.flat_map(& &1.descriptors)
    |> Enum.filter(&(&1.descriptor_digest in descriptor_digests))
    |> Enum.flat_map(fn facts ->
      facts.descriptor.verification_keys
      |> Enum.filter(&(&1.key_id == receipt.envelope.kid and &1.status == :active))
      |> Enum.map(& &1.public_key)
    end)
  end

  defp facts(receipt, projection, verified_context) do
    additions = if match?({:revision, _revision}, verified_context), do: [:signature], else: []
    signing_key_id = if additions == [], do: receipt.envelope.kid, else: nil

    Facts.build(
      ReceiptFacts,
      %{
        receipt_digest: digest(receipt),
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
        chain_conflict: projection.chain_conflict,
        governing_match: projection.governing_match,
        deployment_digest_matched: projection.deployment_digest_matched,
        optional_extensions_retained: []
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
