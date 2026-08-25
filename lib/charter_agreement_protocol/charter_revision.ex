defmodule CharterAgreementProtocol.CharterRevision do
  @moduledoc """
  Closed codec for one unsigned Charter Revision.

  Decoding proves canonical syntax and the revision-local contract. Revision
  chain continuity, acceptance policy, and supersession effects require a
  verified artifact set and are deliberately evaluated by later surfaces.
  """

  alias CharterAgreementProtocol.{
    Canonicalization,
    Digest,
    Error,
    Json,
    Limits,
    Schema,
    Timestamp
  }

  defmodule Party do
    @moduledoc "A revision party binding to one verified descriptor digest."
    @enforce_keys [:party_descriptor_digest, :role]
    defstruct @enforce_keys

    @type t :: %__MODULE__{party_descriptor_digest: binary(), role: binary()}
  end

  defmodule LegalText do
    @moduledoc "The raw-byte digest and descriptive metadata for governing legal text."
    @enforce_keys [:content_digest, :media_type]
    defstruct [:content_digest, :media_type, :uri_hint]

    @type t :: %__MODULE__{
            content_digest: binary(),
            media_type: binary(),
            uri_hint: nil | binary()
          }
  end

  defmodule AttributionDeclaration do
    @moduledoc "The closed attribution basis declared by a revision."
    @enforce_keys [:basis]
    defstruct [:basis, :detail_digest]

    @type t :: %__MODULE__{
            basis: :bound_deployments | :legal_text,
            detail_digest: nil | binary()
          }
  end

  defmodule TerminationRules do
    @moduledoc "The revision-local closed set of termination reason codes."
    @enforce_keys [:reason_codes]
    defstruct @enforce_keys

    @type t :: %__MODULE__{reason_codes: [binary()]}
  end

  defmodule AbpBinding do
    @moduledoc "One exact Agent Blueprint Protocol deployment binding."
    @enforce_keys [
      :party_role,
      :blueprint_id,
      :release_number,
      :content_digest,
      :deployment_digest
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            party_role: binary(),
            blueprint_id: binary(),
            release_number: pos_integer(),
            content_digest: binary(),
            deployment_digest: binary()
          }
  end

  alias __MODULE__.{AbpBinding, AttributionDeclaration, LegalText, Party, TerminationRules}

  @enforce_keys [
    :protocol_revision,
    :revision_number,
    :parties,
    :legal_text,
    :precedence_declaration,
    :attribution_declaration,
    :effective_from,
    :termination_rules,
    :abp_bindings,
    :receipt_profile,
    :supersedes,
    :extensions,
    :canonical_bytes
  ]
  defstruct [
    :protocol_revision,
    :charter_id,
    :revision_number,
    :prev_revision_digest,
    :parties,
    :legal_text,
    :precedence_declaration,
    :attribution_declaration,
    :effective_from,
    :effective_until,
    :termination_rules,
    :abp_bindings,
    :receipt_profile,
    :supersedes,
    :extensions,
    :canonical_bytes
  ]

  @type precedence :: :legal_text_governs | :machine_terms_govern
  @type t :: %__MODULE__{
          protocol_revision: 1,
          charter_id: nil | binary(),
          revision_number: pos_integer(),
          prev_revision_digest: nil | binary(),
          parties: [Party.t()],
          legal_text: LegalText.t(),
          precedence_declaration: precedence(),
          attribution_declaration: AttributionDeclaration.t(),
          effective_from: Timestamp.t(),
          effective_until: nil | Timestamp.t(),
          termination_rules: TerminationRules.t(),
          abp_bindings: [AbpBinding.t()],
          receipt_profile: binary(),
          supersedes: [binary()],
          extensions: Json.value(),
          canonical_bytes: binary()
        }

  @tagged_digest ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/
  @blueprint_id ~r/\A[a-z0-9][a-z0-9._-]*\/[a-z0-9][a-z0-9._-]*\z/
  @receipt_profile ~r/\A[a-z0-9][a-z0-9.-]*\/[a-z0-9][a-z0-9.-]*\z/
  @safe_integer 9_007_199_254_740_991

  @party_definition Schema.definition("charter_revision_party", [
                      Schema.field("party_descriptor_digest",
                        required?: true,
                        types: [:string],
                        constraint: {:matches, @tagged_digest}
                      ),
                      Schema.field("role",
                        required?: true,
                        types: [:string],
                        constraint: {:string_bytes, 1, 128}
                      )
                    ])

  @legal_text_definition Schema.definition("charter_revision_legal_text", [
                           Schema.field("content_digest",
                             required?: true,
                             types: [:string],
                             constraint: {:matches, @tagged_digest}
                           ),
                           Schema.field("media_type",
                             required?: true,
                             types: [:string],
                             constraint: {:string_bytes, 1, 255}
                           ),
                           Schema.field("uri_hint",
                             types: [:string],
                             constraint: {:string_bytes, 1, 2_048}
                           )
                         ])

  @attribution_definition Schema.definition("charter_revision_attribution", [
                            Schema.field("basis",
                              required?: true,
                              types: [:string],
                              constraint:
                                {:one_of,
                                 [{:string, "bound_deployments"}, {:string, "legal_text"}]}
                            ),
                            Schema.field("detail_digest",
                              types: [:string],
                              constraint: {:matches, @tagged_digest}
                            )
                          ])

  @termination_definition Schema.definition("charter_revision_termination", [
                            Schema.field("reason_codes",
                              required?: true,
                              types: [:array],
                              cardinality: {1, 64}
                            )
                          ])

  @binding_definition Schema.definition("charter_revision_abp_binding", [
                        Schema.field("party_role",
                          required?: true,
                          types: [:string],
                          constraint: {:string_bytes, 1, 128}
                        ),
                        Schema.field("blueprint_id",
                          required?: true,
                          types: [:string],
                          constraint: {:all, [{:string_bytes, 3, 512}, {:matches, @blueprint_id}]}
                        ),
                        Schema.field("release_number",
                          required?: true,
                          types: [:integer],
                          constraint: {:integer_range, 1, @safe_integer}
                        ),
                        Schema.field("content_digest",
                          required?: true,
                          types: [:string],
                          constraint: {:matches, @tagged_digest}
                        ),
                        Schema.field("deployment_digest",
                          required?: true,
                          types: [:string],
                          constraint: {:matches, @tagged_digest}
                        )
                      ])

  @definition Schema.definition("charter_revision", [
                Schema.field("protocol_revision",
                  required?: true,
                  types: [:integer],
                  constraint: {:integer_range, 1, 1}
                ),
                Schema.field("charter_id",
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                ),
                Schema.field("revision_number",
                  required?: true,
                  types: [:integer],
                  constraint: {:integer_range, 1, @safe_integer}
                ),
                Schema.field("prev_revision_digest",
                  types: [:string],
                  constraint: {:matches, @tagged_digest}
                ),
                Schema.field("parties",
                  required?: true,
                  types: [:array],
                  cardinality: {2, 2},
                  nested: {:array, @party_definition}
                ),
                Schema.field("legal_text",
                  required?: true,
                  types: [:object],
                  nested: {:object, @legal_text_definition}
                ),
                Schema.field("precedence_declaration",
                  required?: true,
                  types: [:string],
                  constraint:
                    {:one_of,
                     [{:string, "legal_text_governs"}, {:string, "machine_terms_govern"}]}
                ),
                Schema.field("attribution_declaration",
                  required?: true,
                  types: [:object],
                  nested: {:object, @attribution_definition}
                ),
                Schema.field("effective_from", required?: true, types: [:string]),
                Schema.field("effective_until", types: [:string]),
                Schema.field("termination_rules",
                  required?: true,
                  types: [:object],
                  nested: {:object, @termination_definition}
                ),
                Schema.field("abp_bindings",
                  required?: true,
                  types: [:array],
                  cardinality: {0, 64},
                  nested: {:array, @binding_definition}
                ),
                Schema.field("receipt_profile",
                  required?: true,
                  types: [:string],
                  constraint: {:all, [{:string_bytes, 3, 512}, {:matches, @receipt_profile}]}
                ),
                Schema.field("supersedes",
                  types: [:array],
                  cardinality: {0, 8}
                ),
                Schema.field("extensions", required?: true, types: [:object])
              ])

  @doc "Decode and validate one canonical unsigned Charter Revision."
  @spec decode(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def decode(bytes, %Limits{} = limits) do
    if Limits.valid?(limits), do: decode_canonical(bytes, limits), else: invalid_limits()
  end

  def decode(_bytes, _limits), do: {:error, Error.new(:invalid_type, ["limits"])}

  @doc "Return the revision's domain-separated content digest."
  @spec digest(t()) :: binary()
  def digest(%__MODULE__{canonical_bytes: bytes}),
    do: :charter_revision_content |> Digest.hash(bytes) |> Digest.to_tagged()

  defp decode_canonical(bytes, limits) do
    with {:ok, value} <- Json.decode(bytes, limits),
         {:ok, canonical} <- Canonicalization.encode(value),
         :ok <- exact_bytes(bytes, canonical),
         {:ok, validated} <- Schema.validate(@definition, value) do
      extract(validated, bytes)
    end
  end

  defp exact_bytes(bytes, bytes), do: :ok

  defp exact_bytes(_received, _canonical),
    do: {:error, Error.new(:non_canonical_bytes, ["charter_revision"])}

  defp extract({:object, members}, bytes) do
    values = Map.new(members)
    {:integer, revision_number} = values["revision_number"]

    with {:ok, charter_id} <- optional_digest(values, "charter_id"),
         {:ok, previous} <- optional_digest(values, "prev_revision_digest"),
         {:ok, parties} <- parties(values["parties"]),
         {:ok, legal_text} <- legal_text(values["legal_text"]),
         {:ok, precedence} <- precedence(values["precedence_declaration"]),
         {:ok, attribution} <- attribution(values["attribution_declaration"]),
         {:ok, effective_from} <- timestamp(values["effective_from"]),
         {:ok, effective_until} <- optional_timestamp(values, "effective_until"),
         {:ok, termination} <- termination(values["termination_rules"]),
         {:ok, bindings} <- bindings(values["abp_bindings"]),
         {:string, receipt_profile} <- values["receipt_profile"],
         {:ok, supersedes} <- supersedes(values),
         :ok <- extensions(values["extensions"]),
         :ok <- genesis_shape(revision_number, charter_id, previous),
         :ok <- ordered_interval(effective_from, effective_until),
         :ok <- unique_roles(parties),
         :ok <- binding_roles(bindings, parties) do
      {:ok,
       %__MODULE__{
         protocol_revision: 1,
         charter_id: charter_id,
         revision_number: revision_number,
         prev_revision_digest: previous,
         parties: parties,
         legal_text: legal_text,
         precedence_declaration: precedence,
         attribution_declaration: attribution,
         effective_from: effective_from,
         effective_until: effective_until,
         termination_rules: termination,
         abp_bindings: bindings,
         receipt_profile: receipt_profile,
         supersedes: supersedes,
         extensions: values["extensions"],
         canonical_bytes: bytes
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp parties({:array, values}) do
    collect(values, fn {:object, members} ->
      value = Map.new(members)
      {:string, digest} = value["party_descriptor_digest"]
      {:string, role} = value["role"]

      with :ok <- valid_digest(digest) do
        {:ok, %Party{party_descriptor_digest: digest, role: role}}
      end
    end)
  end

  defp legal_text({:object, members}) do
    value = Map.new(members)
    {:string, content_digest} = value["content_digest"]
    {:string, media_type} = value["media_type"]

    with :ok <- valid_digest(content_digest),
         {:ok, uri_hint} <- optional_string(value, "uri_hint") do
      {:ok,
       %LegalText{
         content_digest: content_digest,
         media_type: media_type,
         uri_hint: uri_hint
       }}
    end
  end

  defp precedence({:string, "legal_text_governs"}), do: {:ok, :legal_text_governs}
  defp precedence({:string, "machine_terms_govern"}), do: {:ok, :machine_terms_govern}

  defp attribution({:object, members}) do
    value = Map.new(members)

    with {:ok, basis} <- attribution_basis(value["basis"]),
         {:ok, detail_digest} <- optional_digest(value, "detail_digest") do
      {:ok, %AttributionDeclaration{basis: basis, detail_digest: detail_digest}}
    end
  end

  defp attribution_basis({:string, "bound_deployments"}), do: {:ok, :bound_deployments}
  defp attribution_basis({:string, "legal_text"}), do: {:ok, :legal_text}

  defp termination({:object, members}) do
    %{"reason_codes" => {:array, reason_values}} = Map.new(members)

    with {:ok, reason_codes} <- bounded_strings(reason_values, 128),
         true <- reason_codes == Enum.uniq(reason_codes) do
      {:ok, %TerminationRules{reason_codes: reason_codes}}
    else
      _failure -> revision_error()
    end
  end

  defp bindings({:array, values}) do
    collect(values, fn {:object, members} ->
      value = Map.new(members)
      {:string, party_role} = value["party_role"]
      {:string, blueprint_id} = value["blueprint_id"]
      {:integer, release_number} = value["release_number"]
      {:string, content_digest} = value["content_digest"]
      {:string, deployment_digest} = value["deployment_digest"]

      with :ok <- valid_digest(content_digest),
           :ok <- valid_digest(deployment_digest) do
        {:ok,
         %AbpBinding{
           party_role: party_role,
           blueprint_id: blueprint_id,
           release_number: release_number,
           content_digest: content_digest,
           deployment_digest: deployment_digest
         }}
      end
    end)
  end

  defp supersedes(values) do
    case Map.fetch(values, "supersedes") do
      :error ->
        {:ok, []}

      {:ok, {:array, digests}} ->
        with {:ok, tagged} <- collect(digests, &tagged_digest/1),
             true <- tagged == Enum.uniq(tagged) do
          {:ok, tagged}
        else
          _failure -> revision_error()
        end
    end
  end

  defp tagged_digest({:string, tagged}) do
    with :ok <- valid_digest(tagged), do: {:ok, tagged}
  end

  defp optional_digest(values, name) do
    case Map.fetch(values, name) do
      :error -> {:ok, nil}
      {:ok, {:string, tagged}} -> with :ok <- valid_digest(tagged), do: {:ok, tagged}
    end
  end

  defp valid_digest(tagged) do
    case Digest.from_tagged(tagged) do
      {:ok, _digest} -> :ok
      _error -> revision_error()
    end
  end

  defp timestamp({:string, value}), do: Timestamp.parse(value)

  defp optional_timestamp(values, name) do
    case Map.fetch(values, name) do
      :error -> {:ok, nil}
      {:ok, value} -> timestamp(value)
    end
  end

  defp optional_string(values, name) do
    case Map.fetch(values, name) do
      :error -> {:ok, nil}
      {:ok, {:string, value}} -> {:ok, value}
    end
  end

  defp bounded_strings(values, maximum_bytes) do
    collect(values, fn
      {:string, value} when byte_size(value) in 1..maximum_bytes//1 -> {:ok, value}
      _value -> revision_error()
    end)
  end

  defp collect(values, extractor), do: collect(values, extractor, [])
  defp collect([], _extractor, acc), do: {:ok, Enum.reverse(acc)}

  defp collect([value | rest], extractor, acc) do
    case extractor.(value) do
      {:ok, extracted} -> collect(rest, extractor, [extracted | acc])
      {:error, %Error{}} = error -> error
    end
  end

  defp extensions({:object, members}) do
    case Map.new(members) do
      %{"critical" => {:object, []}, "optional" => {:object, _}} when length(members) == 2 -> :ok
      _value -> revision_error()
    end
  end

  defp genesis_shape(1, nil, nil), do: :ok

  defp genesis_shape(number, charter_id, previous)
       when number > 1 and is_binary(charter_id) and is_binary(previous),
       do: :ok

  defp genesis_shape(_number, _charter_id, _previous), do: revision_error()

  defp ordered_interval(_from, nil), do: :ok

  defp ordered_interval(from, until) do
    if Timestamp.compare(from, until) == :lt, do: :ok, else: revision_error()
  end

  defp unique_roles(parties) do
    roles = Enum.map(parties, & &1.role)
    if roles == Enum.uniq(roles), do: :ok, else: revision_error()
  end

  defp binding_roles(bindings, parties) do
    roles = MapSet.new(parties, & &1.role)

    if Enum.all?(bindings, &MapSet.member?(roles, &1.party_role)),
      do: :ok,
      else: revision_error()
  end

  defp revision_error, do: {:error, Error.new(:revision_invalid, ["charter_revision"])}
  defp invalid_limits, do: {:error, Error.new(:invalid_limits, ["limits"])}
end
