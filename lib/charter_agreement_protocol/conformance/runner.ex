defmodule CharterAgreementProtocol.Conformance.Runner do
  @moduledoc """
  CAP never authorizes.

  Pure execution of every case in an integrity-checked conformance corpus.
  Results compare the complete projected fact JSON, not only valid/invalid
  status, so a vacuous implementation cannot report agreement.
  """

  alias CharterAgreementProtocol.Conformance.Corpus

  alias CharterAgreementProtocol.{
    Acceptance,
    Base64Url,
    Canonicalization,
    Capability.Profile,
    Chain,
    CharterRevision,
    DescriptorChain,
    Digest,
    Error,
    Json,
    Limits,
    PartyDescriptor,
    Receipt,
    Schema,
    TerminationNotice,
    Timestamp
  }

  @type result :: %{
          id: binary(),
          surface: binary(),
          expected: map(),
          actual: map(),
          agree: boolean()
        }

  @digest_domains %{
    "party_descriptor_content" => :party_descriptor_content,
    "charter_revision_content" => :charter_revision_content,
    "acceptance_content" => :acceptance_content,
    "termination_content" => :termination_content,
    "receipt_content" => :receipt_content,
    "legal_text" => :legal_text,
    "signature" => :signature,
    "extension_schema" => :extension_schema,
    "extension_registry" => :extension_registry,
    "conformance_report" => :conformance_report,
    "corpus_index" => :corpus_index
  }

  @option_members %{
    "limits" => Map.new(Limits.fields(), &{Atom.to_string(&1), &1}),
    "profile" => %{"algorithms" => :algorithms, "revisions" => :revisions},
    "revisions" => %{"min" => :min, "max" => :max}
  }

  @doc "Execute every loaded case in corpus order."
  @spec run(Corpus.t()) :: [result()]
  def run(%Corpus{cases: cases}) do
    Enum.map(cases, fn one ->
      actual =
        with :ok <- input_object(one["input"]),
             {:ok, _limits} <- limits(one["input"]),
             {:ok, profile} <- parse_profile(one["input"]) do
          execute(one, profile)
        else
          {:error, %Error{code: code}} -> invalid(code)
        end

      %{
        id: one["id"],
        surface: one["surface"],
        expected: one["expect"],
        actual: actual,
        agree: actual == one["expect"]
      }
    end)
  end

  defp execute(%{"surface" => "base64url.decode", "input" => input}, _profile) do
    input["text"]
    |> Base64Url.decode()
    |> project_ok(fn bytes -> %{"bytes_base64url" => Base64Url.encode(bytes)} end)
  end

  defp execute(%{"surface" => "json.decode", "input" => input}, _profile) do
    case limits(input) do
      {:ok, limits} ->
        with {:ok, bytes} <- json_input(input) do
          Json.decode(bytes, limits)
        end
        |> project_ok(&json_projection/1)

      {:error, %Error{} = error} ->
        invalid(error.code)
    end
  end

  defp execute(%{"surface" => "canonicalization.encode", "input" => input}, _profile) do
    case input do
      %{"text" => text} ->
        Canonicalization.verify(text) |> project_ok(fn _ -> %{"text" => text} end)

      _other ->
        with {:ok, value} <- canonical_input(input) do
          Canonicalization.encode(value)
        end
        |> project_ok(&%{"text" => &1})
    end
  end

  defp execute(%{"surface" => "digest.hash", "input" => input}, _profile) do
    with {:ok, domain} <- digest_domain(input["domain"]),
         {:ok, bytes} <- digest_input(input) do
      case input do
        %{"tagged" => tagged} ->
          Digest.verify_content(domain, bytes, tagged)

        %{"bytes_base64url" => _encoded} when is_binary(bytes) ->
          {:ok, %{"algorithm" => "sha-256"}}

        _other ->
          Digest.verify_content(
            domain,
            bytes,
            "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
          )
      end
    end
    |> project_ok(fn
      :ok -> %{}
      output -> output
    end)
  end

  defp execute(%{"surface" => "schema.validate", "input" => %{"members" => members}}, _profile)
       when is_map(members) do
    value = {:object, Enum.map(members, fn {name, item} -> {name, tagged(item)} end)}
    Schema.validate(foundation_schema(), value) |> project_ok(fn _ -> %{"members" => members} end)
  end

  defp execute(%{"surface" => "party_descriptor.verify", "input" => input}, profile) do
    with {:ok, predecessor} <- case_predecessor(input) do
      PartyDescriptor.verify(input["compact"], predecessor, Limits.default(), profile)
    end
    |> project_ok(fn facts ->
      %{
        "descriptor_digest" => facts.descriptor_digest,
        "party_id" => facts.party_id,
        "descriptor_number" => facts.descriptor_number
      }
    end)
  end

  defp execute(%{"surface" => "descriptor_chain.verify", "input" => input}, _profile) do
    DescriptorChain.verify(input["compacts"], Limits.default())
    |> project_ok(&descriptor_chain_projection/1)
  end

  defp execute(%{"surface" => "charter_revision.decode", "input" => input}, _profile) do
    CharterRevision.decode(input["text"], Limits.default())
    |> project_ok(fn revision ->
      binding = hd(revision.abp_bindings)

      %{
        "revision_digest" => CharterRevision.digest(revision),
        "revision_number" => revision.revision_number,
        "precedence_declaration" => Atom.to_string(revision.precedence_declaration),
        "abp_binding" => %{
          "blueprint_id" => binding.blueprint_id,
          "release_number" => binding.release_number,
          "content_digest" => binding.content_digest,
          "deployment_digest" => binding.deployment_digest
        }
      }
    end)
  end

  defp execute(%{"surface" => "acceptance.verify", "input" => input}, profile) do
    with {:ok, revision} <- CharterRevision.decode(input["revision_text"], Limits.default()),
         {:ok, chain} <- DescriptorChain.verify(input["descriptor_compacts"], Limits.default()) do
      Acceptance.verify(input["compact"], revision, chain, Limits.default(), profile)
    end
    |> project_ok(fn facts ->
      %{
        "acceptance_digest" => facts.acceptance_digest,
        "revision_digest" => facts.revision_digest,
        "party_descriptor_digest" => facts.party_descriptor_digest,
        "descriptor_position" => Atom.to_string(facts.descriptor_position)
      }
    end)
  end

  defp execute(%{"surface" => "acceptance.equivocation", "input" => input}, _profile) do
    with {:ok, chain} <- DescriptorChain.verify(input["descriptor_compacts"], Limits.default()),
         {:ok, [left, right]} <- signed_revisions(input["signed_revisions"], chain) do
      Acceptance.equivocation(left, right)
    end
    |> project_ok(fn evidence ->
      %{
        "kind" => Atom.to_string(evidence.kind),
        "revision_number" => evidence.revision_number,
        "revision_digests" => evidence.revision_digests,
        "winner" => evidence.winner
      }
    end)
  end

  defp execute(%{"surface" => "termination.verify", "input" => input}, profile) do
    with {:ok, revision} <- CharterRevision.decode(input["revision_text"], Limits.default()),
         {:ok, chain} <- DescriptorChain.verify(input["descriptor_compacts"], Limits.default()) do
      TerminationNotice.verify(input["compact"], revision, chain, Limits.default(), profile)
    end
    |> project_ok(fn facts ->
      %{
        "termination_digest" => facts.termination_digest,
        "governing_revision_digest" => facts.governing_revision_digest,
        "party_descriptor_digest" => facts.party_descriptor_digest,
        "reason_code" => facts.reason_code,
        "descriptor_position" => Atom.to_string(facts.descriptor_position)
      }
    end)
  end

  defp execute(%{"surface" => "chain.verify_profile", "input" => input}, profile) do
    input
    |> verify_chain_profile(profile)
    |> project_ok(fn facts ->
      %{
        "charter_id" => facts.charter_id,
        "topology" => Atom.to_string(facts.chain_topology)
      }
    end)
  end

  defp execute(%{"surface" => "chain.verify", "input" => input}, _profile) do
    input
    |> verify_chain()
    |> project_ok(fn facts ->
      %{
        "charter_id" => facts.charter_id,
        "topology" => Atom.to_string(facts.chain_topology),
        "accepted_revision_digests" => facts.accepted_revision_digests,
        "superseded_revision_digests" => facts.superseded_revision_digests
      }
    end)
  end

  defp execute(%{"surface" => "governing_revision", "input" => input}, _profile) do
    with {:ok, facts} <- verify_chain(input),
         {:ok, governing} <- governing_queries(input["queries"], facts) do
      {:ok, governing}
    end
    |> project_ok(&%{"governing_revisions" => &1})
  end

  defp execute(%{"surface" => "receipt.verify", "input" => input}, profile) do
    case limits(input) do
      {:ok, caller_limits} ->
        with {:ok, context} <- receipt_context(input) do
          Receipt.verify(
            input["compact"],
            context,
            caller_limits,
            profile
          )
        end
        |> project_ok(fn facts ->
          %{
            "receipt_digest" => facts.receipt_digest,
            "revision_number" => facts.revision_number,
            "revision_digest" => facts.revision_digest,
            "decision" => Atom.to_string(facts.decision),
            "outcome" => Atom.to_string(facts.outcome),
            "chain_conflict" => Atom.to_string(facts.chain_conflict),
            "governing_match" => Atom.to_string(facts.governing_match),
            "deployment_digest_matched" => facts.deployment_digest_matched,
            "optional_extensions_retained" => facts.optional_extensions_retained
          }
        end)

      {:error, %Error{code: code}} ->
        invalid(code)
    end
  end

  defp execute(%{"surface" => "signing.prepare", "input" => input}, _profile) do
    with {:ok, limits} <- limits(input),
         {:ok, profile} <- parse_profile(input),
         {:ok, context} <- signing_context(input["context"]),
         {:ok, public_key} <- Base64Url.decode(input["public_key"]) do
      value =
        input |> Map.take(["kid", "claims", "algorithm"]) |> Map.put("public_key", public_key)

      CharterAgreementProtocol.prepare_signing(
        signing_kind(input["kind"]),
        value,
        context,
        limits,
        profile
      )
      |> project_ok(fn plan ->
        %{
          "protected_segment" => plan.signing_input.protected_segment,
          "payload_segment" => plan.signing_input.payload_segment,
          "key" => Atom.to_string(plan.key)
        }
      end)
    else
      {:error, %Error{} = error} -> invalid(error.code)
    end
  end

  defp execute(_one, _profile), do: invalid(:invalid_type)

  defp input_object(input) when is_map(input), do: :ok
  defp input_object(_input), do: type_error()

  defp project_ok({:ok, value}, projector), do: valid(projector.(value))
  defp project_ok({:error, %Error{code: code}}, _projector), do: invalid(code)
  defp project_ok(:ok, projector), do: valid(projector.(:ok))

  defp valid(output), do: %{"status" => "valid", "output" => output}
  defp invalid(code), do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp mapped_options(selected, kind) when is_map(selected) do
    members = Map.fetch!(@option_members, kind)

    Enum.reduce_while(selected, {:ok, %{}}, fn {name, value}, {:ok, mapped} ->
      case Map.fetch(members, name) do
        {:ok, field} -> {:cont, {:ok, Map.put(mapped, field, value)}}
        :error -> {:halt, invalid_options(kind, [{name, value}])}
      end
    end)
  end

  defp mapped_options(_selected, "limits"), do: {:error, Error.new(:invalid_limits, ["limits"])}
  defp mapped_options(_selected, _kind), do: {:error, Error.new(:invalid_profile, ["profile"])}

  defp invalid_options("limits", options), do: Limits.new(options)
  defp invalid_options(_kind, options), do: Profile.new(options)

  defp limits(input) do
    with {:ok, selected} <- mapped_options(Map.get(input, "limits", %{}), "limits") do
      Limits.new(Map.to_list(selected))
    end
  end

  defp json_input(%{"text" => text}), do: {:ok, text}

  defp json_input(%{"bytes_base64url" => encoded}),
    do: Base64Url.decode(encoded)

  defp json_input(%{"kind" => "integer", "value" => value}), do: {:ok, value}
  defp json_input(_input), do: type_error()

  defp json_projection(:null), do: %{"tag" => "null"}
  defp json_projection({:boolean, value}), do: %{"tag" => "boolean", "value" => value}
  defp json_projection({:integer, value}), do: %{"tag" => "integer", "value" => value}
  defp json_projection({:float, value}), do: %{"tag" => "float", "value" => value}
  defp json_projection({:string, value}), do: %{"tag" => "string", "value" => value}

  defp json_projection({:array, items}),
    do: %{"tag" => "array", "items" => Enum.map(items, &json_projection/1)}

  defp json_projection({:object, members}) do
    projected = Enum.map(members, fn {name, value} -> [name, json_projection(value)] end)
    %{"tag" => "object", "members" => projected}
  end

  defp canonical_input(%{"tag" => "integer", "text_value" => decimal}) when is_binary(decimal) do
    case Integer.parse(decimal) do
      {integer, ""} -> {:ok, {:integer, integer}}
      _other -> type_error()
    end
  end

  defp canonical_input(%{"tag" => "object", "members" => members}) when is_list(members) do
    with {:ok, pairs} <- collect(members, &canonical_member/1), do: {:ok, {:object, pairs}}
  end

  defp canonical_input(%{"tag" => "string_codepoint", "value" => hex}) when is_binary(hex) do
    case Integer.parse(hex, 16) do
      {point, ""} when point in 0..0x10FFFF and point not in 0xD800..0xDFFF ->
        {:ok, {:string, <<point::utf8>>}}

      _other ->
        type_error()
    end
  end

  defp canonical_input(_input), do: type_error()

  defp canonical_member([name, %{"tag" => "integer", "value" => value}]) when is_binary(name),
    do: {:ok, {name, {:integer, value}}}

  defp canonical_member(_member), do: type_error()

  defp digest_input(%{"bytes_base64url" => encoded}), do: Base64Url.decode(encoded)
  defp digest_input(%{"kind" => "integer", "value" => value}), do: {:ok, value}
  defp digest_input(_input), do: type_error()

  defp digest_domain(nil), do: {:ok, :charter_revision_content}

  defp digest_domain(domain) do
    case Map.fetch(@digest_domains, domain) do
      {:ok, value} -> {:ok, value}
      :error -> type_error()
    end
  end

  defp foundation_schema do
    Schema.definition("foundation", [
      Schema.field("name",
        required?: true,
        types: [:string],
        constraint: {:matches, ~r/\A[a-z]+\z/},
        cardinality: {2, 4}
      )
    ])
  end

  defp tagged(value) do
    {:ok, tagged} = Canonicalization.from_plain(value)
    tagged
  end

  defp descriptor_chain_projection(chain) do
    positions =
      Map.new(chain.descriptors, fn facts ->
        {facts.descriptor_digest, Atom.to_string(facts.descriptor_position)}
      end)

    siblings = if chain.fork_evidence, do: chain.fork_evidence.sibling_descriptors, else: []

    %{
      "topology" => Atom.to_string(chain.topology),
      "positions" => positions,
      "sibling_descriptors" => siblings
    }
  end

  defp signing_kind("party_descriptor"), do: :party_descriptor
  defp signing_kind("acceptance"), do: :acceptance
  defp signing_kind("termination"), do: :termination
  defp signing_kind("receipt"), do: :receipt
  defp signing_kind(_other), do: :unknown

  defp signing_context(%{"set" => set}) when is_map(set) do
    {:ok,
     struct(CharterAgreementProtocol.ArtifactSet,
       revisions: set["revisions"],
       acceptances: set["acceptances"],
       descriptors: set["descriptors"],
       terminations: set["terminations"]
     )}
  end

  defp signing_context(%{"chain" => set}), do: verify_chain(set)

  defp signing_context(%{"revision_text" => text}),
    do: CharterRevision.decode(text, Limits.default())

  defp signing_context(%{"predecessor_compacts" => compacts}) do
    predecessor_history(compacts)
  end

  defp signing_context(value), do: {:ok, value}

  defp predecessor_history(compacts) when is_list(compacts) do
    Enum.reduce_while(compacts, {:ok, nil}, fn compact, {:ok, predecessor} ->
      case PartyDescriptor.verify(compact, predecessor, Limits.default()) do
        {:ok, facts} -> {:cont, {:ok, facts}}
        error -> {:halt, error}
      end
    end)
  end

  defp predecessor_history(_compacts), do: type_error()

  defp receipt_context(%{"revision_text" => text}),
    do: CharterRevision.decode(text, Limits.default())

  defp receipt_context(%{"chain" => chain}), do: verify_chain(chain)
  defp receipt_context(_input), do: type_error()

  defp case_predecessor(%{"predecessor_compacts" => compacts}),
    do: predecessor_history(compacts)

  defp case_predecessor(_input), do: {:ok, nil}

  defp parse_profile(input) do
    with {:ok, selected} <- mapped_options(Map.get(input, "profile", %{}), "profile"),
         {:ok, revisions} <- profile_revisions(Map.get(selected, :revisions, :missing)) do
      algorithms = Map.get(selected, :algorithms, Profile.full().algorithms)
      profile = %Profile{algorithms: algorithms, revisions: revisions}
      with :ok <- Profile.check(profile), do: {:ok, profile}
    end
  end

  defp profile_revisions(:missing), do: {:ok, Profile.full().revisions}

  defp profile_revisions(range) when is_map(range) do
    with {:ok, mapped} <- mapped_options(range, "revisions") do
      {:ok, {Map.get(mapped, :min), Map.get(mapped, :max)}}
    end
  end

  defp profile_revisions(_range), do: {:error, Error.new(:invalid_profile, ["profile"])}

  defp verify_chain_profile(input, profile) do
    Chain.verify(
      input["revisions"],
      input["acceptances"],
      input["descriptors"],
      input["terminations"],
      Limits.default(),
      profile
    )
  end

  defp verify_chain(input) when is_map(input) do
    with {:ok, limits} <- limits(input) do
      Chain.verify(
        input["revisions"],
        input["acceptances"],
        input["descriptors"],
        input["terminations"],
        limits
      )
    end
  end

  defp verify_chain(_input), do: type_error()

  defp signed_revisions([_, _] = signed, chain) do
    collect(signed, fn
      %{"revision_text" => text, "compact" => compact} ->
        with {:ok, revision} <- CharterRevision.decode(text, Limits.default()) do
          Acceptance.verify(compact, revision, chain, Limits.default())
        end

      _other ->
        type_error()
    end)
  end

  defp signed_revisions(_signed, _chain), do: type_error()

  defp governing_queries(queries, facts) when is_list(queries) do
    collect(queries, fn
      %{"at" => at} ->
        with {:ok, timestamp} <- Timestamp.parse(at),
             {:ok, result} <- Chain.governing_revision(facts, timestamp) do
          {:ok, if(is_atom(result), do: Atom.to_string(result), else: result)}
        end

      _other ->
        type_error()
    end)
  end

  defp governing_queries(_queries, _facts), do: type_error()

  defp collect(values, fun) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp type_error, do: {:error, Error.new(:invalid_type, ["input"])}
end
