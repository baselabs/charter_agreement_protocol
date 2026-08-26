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
    TerminationNotice
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

  @doc "Execute every loaded case in corpus order."
  @spec run(Corpus.t()) :: [result()]
  def run(%Corpus{cases: cases}) do
    Enum.map(cases, fn one ->
      actual = execute(one)

      %{
        id: one["id"],
        surface: one["surface"],
        expected: one["expect"],
        actual: actual,
        agree: actual == one["expect"]
      }
    end)
  end

  defp execute(%{"surface" => "base64url.decode", "input" => input}) do
    input["text"]
    |> Base64Url.decode()
    |> project_ok(fn bytes -> %{"bytes_base64url" => Base64Url.encode(bytes)} end)
  end

  defp execute(%{"surface" => "json.decode", "input" => input}) do
    case limits(input) do
      {:ok, limits} ->
        input |> json_input() |> Json.decode(limits) |> project_ok(&json_projection/1)

      {:error, %Error{} = error} ->
        invalid(error.code)
    end
  end

  defp execute(%{"surface" => "canonicalization.encode", "input" => input}) do
    case input do
      %{"text" => text} ->
        Canonicalization.verify(text) |> project_ok(fn _ -> %{"text" => text} end)

      _other ->
        input |> canonical_input() |> Canonicalization.encode() |> project_ok(&%{"text" => &1})
    end
  end

  defp execute(%{"surface" => "digest.hash", "input" => input}) do
    domain = digest_domain(input["domain"])
    bytes = digest_input(input)

    case input do
      %{"tagged" => tagged} ->
        Digest.verify_content(domain, bytes, tagged) |> project_ok(fn :ok -> %{} end)

      %{"bytes_base64url" => _encoded} ->
        project_ok({:ok, Digest.hash(domain, bytes)}, fn _ -> %{"algorithm" => "sha-256"} end)

      _other ->
        Digest.verify_content(
          domain,
          bytes,
          "sha-256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )
        |> project_ok(fn :ok -> %{} end)
    end
  end

  defp execute(%{"surface" => "schema.validate", "input" => %{"members" => members}}) do
    value = {:object, Enum.map(members, fn {name, item} -> {name, tagged(item)} end)}
    Schema.validate(foundation_schema(), value) |> project_ok(fn _ -> %{"members" => members} end)
  end

  defp execute(%{"surface" => "party_descriptor.verify", "input" => input}) do
    PartyDescriptor.verify(input["compact"], nil, Limits.default())
    |> project_ok(fn facts ->
      %{
        "descriptor_digest" => facts.descriptor_digest,
        "party_id" => facts.party_id,
        "descriptor_number" => facts.descriptor_number
      }
    end)
  end

  defp execute(%{"surface" => "descriptor_chain.verify", "input" => input}) do
    DescriptorChain.verify(input["compacts"], Limits.default())
    |> project_ok(&descriptor_chain_projection/1)
  end

  defp execute(%{"surface" => "charter_revision.decode", "input" => input}) do
    CharterRevision.decode(input["text"], Limits.default())
    |> project_ok(fn revision ->
      [binding] = revision.abp_bindings

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

  defp execute(%{"surface" => "acceptance.verify", "input" => input}) do
    {:ok, revision} = CharterRevision.decode(input["revision_text"], Limits.default())
    {:ok, chain} = DescriptorChain.verify(input["descriptor_compacts"], Limits.default())

    Acceptance.verify(input["compact"], revision, chain, Limits.default())
    |> project_ok(fn facts ->
      %{
        "acceptance_digest" => facts.acceptance_digest,
        "revision_digest" => facts.revision_digest,
        "party_descriptor_digest" => facts.party_descriptor_digest,
        "descriptor_position" => Atom.to_string(facts.descriptor_position)
      }
    end)
  end

  defp execute(%{"surface" => "acceptance.equivocation", "input" => input}) do
    {:ok, chain} = DescriptorChain.verify(input["descriptor_compacts"], Limits.default())

    facts =
      Enum.map(input["signed_revisions"], fn signed ->
        {:ok, revision} = CharterRevision.decode(signed["revision_text"], Limits.default())
        {:ok, one} = Acceptance.verify(signed["compact"], revision, chain, Limits.default())
        one
      end)

    Acceptance.equivocation(Enum.at(facts, 0), Enum.at(facts, 1))
    |> project_ok(fn evidence ->
      %{
        "kind" => Atom.to_string(evidence.kind),
        "revision_number" => evidence.revision_number,
        "revision_digests" => evidence.revision_digests,
        "winner" => evidence.winner
      }
    end)
  end

  defp execute(%{"surface" => "termination.verify", "input" => input}) do
    {:ok, revision} = CharterRevision.decode(input["revision_text"], Limits.default())
    {:ok, chain} = DescriptorChain.verify(input["descriptor_compacts"], Limits.default())

    TerminationNotice.verify(input["compact"], revision, chain, Limits.default())
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

  defp execute(%{"surface" => "chain.verify", "input" => input}) do
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

  defp execute(%{"surface" => "governing_revision", "input" => input}) do
    {:ok, facts} = verify_chain(input)

    governing =
      Enum.map(input["queries"], fn query ->
        {:ok, at, 0} = DateTime.from_iso8601(query["at"])
        {:ok, result} = Chain.governing_revision(facts, at)
        if is_atom(result), do: Atom.to_string(result), else: result
      end)

    valid(%{"governing_revisions" => governing})
  end

  defp execute(%{"surface" => "receipt.verify", "input" => input}) do
    {:ok, chain} = verify_chain(input["chain"])

    Receipt.verify(input["compact"], chain, Limits.default())
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
  end

  defp project_ok({:ok, value}, projector), do: valid(projector.(value))
  defp project_ok({:error, %Error{code: code}}, _projector), do: invalid(code)
  defp project_ok(:ok, projector), do: valid(projector.(:ok))

  defp valid(output), do: %{"status" => "valid", "output" => output}
  defp invalid(code), do: %{"status" => "invalid", "error_code" => Atom.to_string(code)}

  defp limits(%{"limits" => selected}) do
    options = Enum.map(selected, fn {name, value} -> {String.to_existing_atom(name), value} end)
    Limits.new(options)
  end

  defp limits(_input), do: {:ok, Limits.default()}

  defp json_input(%{"text" => text}), do: text

  defp json_input(%{"bytes_base64url" => encoded}),
    do: Base.url_decode64!(encoded, padding: false)

  defp json_input(%{"kind" => "integer", "value" => value}), do: value

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

  defp canonical_input(%{"tag" => "integer", "text_value" => decimal}),
    do: {:integer, String.to_integer(decimal)}

  defp canonical_input(%{"tag" => "object", "members" => members}) do
    {:object, Enum.map(members, fn [name, value] -> {name, tagged_projection(value)} end)}
  end

  defp canonical_input(%{"tag" => "string_codepoint", "value" => hex}) do
    {:string, <<String.to_integer(hex, 16)::utf8>>}
  end

  defp canonical_input(%{"kind" => "improper_object"}),
    do: {:object, :improper}

  defp tagged_projection(%{"tag" => "integer", "value" => value}), do: {:integer, value}

  defp digest_input(%{"bytes_base64url" => encoded}),
    do: Base.url_decode64!(encoded, padding: false)

  defp digest_input(%{"kind" => "integer", "value" => value}), do: value

  defp digest_domain(nil), do: :charter_revision_content
  defp digest_domain(domain), do: Map.fetch!(@digest_domains, domain)

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

  defp tagged(value) when is_boolean(value), do: {:boolean, value}
  defp tagged(value) when is_integer(value), do: {:integer, value}
  defp tagged(value) when is_binary(value), do: {:string, value}

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

  defp verify_chain(input) do
    Chain.verify(
      input["revisions"],
      input["acceptances"],
      input["descriptors"],
      input["terminations"],
      Limits.default()
    )
  end
end
