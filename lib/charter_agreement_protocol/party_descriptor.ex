defmodule CharterAgreementProtocol.PartyDescriptor do
  @moduledoc """
  Closed Party Descriptor codec and predecessor-bound signature verifier.

  Descriptor-chain continuity proves possession linkage between key sets. It
  does not establish organizational identity, legal validity, or authority.
  """

  alias CharterAgreementProtocol.{
    Base64Url,
    CompactJws,
    DescriptorFacts,
    Digest,
    Error,
    Limits,
    Schema,
    Timestamp
  }

  defmodule VerificationKey do
    @moduledoc "One closed Ed25519 verification-key record."
    @enforce_keys [:key_id, :algorithm, :public_key, :status]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            key_id: binary(),
            algorithm: :ed25519,
            public_key: <<_::256>>,
            status: :active | :retired
          }
  end

  defmodule AttestationHint do
    @moduledoc "One non-normative pointer that CAP never dereferences."
    @enforce_keys [:kind, :uri]
    defstruct @enforce_keys

    @type t :: %__MODULE__{kind: binary(), uri: binary()}
  end

  alias __MODULE__.{AttestationHint, VerificationKey}

  @enforce_keys [
    :protocol_revision,
    :descriptor_number,
    :verification_keys,
    :attestation_hints,
    :extensions,
    :effective_from,
    :envelope
  ]
  defstruct [
    :protocol_revision,
    :party_id,
    :descriptor_number,
    :prev_descriptor_digest,
    :verification_keys,
    :attestation_hints,
    :extensions,
    :effective_from,
    :envelope
  ]

  @type t :: %__MODULE__{
          protocol_revision: 1,
          party_id: nil | binary(),
          descriptor_number: pos_integer(),
          prev_descriptor_digest: nil | binary(),
          verification_keys: [VerificationKey.t()],
          attestation_hints: [AttestationHint.t()],
          extensions: CharterAgreementProtocol.Json.value(),
          effective_from: Timestamp.t(),
          envelope: CompactJws.t()
        }

  @key_id ~r/\A[A-Za-z0-9._~-]{1,128}\z/
  @b64url_32 ~r/\A[A-Za-z0-9_-]{43}\z/

  @key_definition Schema.definition("verification_key", [
                    Schema.field("key_id",
                      required?: true,
                      types: [:string],
                      constraint: {:matches, @key_id}
                    ),
                    Schema.field("algorithm",
                      required?: true,
                      types: [:string],
                      constraint: {:one_of, [{:string, "Ed25519"}]}
                    ),
                    Schema.field("public_key",
                      required?: true,
                      types: [:string],
                      constraint: {:matches, @b64url_32}
                    ),
                    Schema.field("status",
                      required?: true,
                      types: [:string],
                      constraint: {:one_of, [{:string, "active"}, {:string, "retired"}]}
                    )
                  ])

  @hint_definition Schema.definition("attestation_hint", [
                     Schema.field("kind",
                       required?: true,
                       types: [:string],
                       constraint: {:string_bytes, 1, 64}
                     ),
                     Schema.field("uri",
                       required?: true,
                       types: [:string],
                       constraint: {:string_bytes, 1, 2_048}
                     )
                   ])

  @definition Schema.definition("party_descriptor", [
                Schema.field("protocol_revision",
                  required?: true,
                  types: [:integer],
                  constraint: {:integer_range, 1, 1}
                ),
                Schema.field("party_id",
                  types: [:string],
                  constraint: {:matches, ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/}
                ),
                Schema.field("descriptor_number",
                  required?: true,
                  types: [:integer],
                  constraint: {:integer_range, 1, 9_007_199_254_740_991}
                ),
                Schema.field("prev_descriptor_digest",
                  types: [:string],
                  constraint: {:matches, ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/}
                ),
                Schema.field("verification_keys",
                  required?: true,
                  types: [:array],
                  cardinality: {1, 32},
                  nested: {:array, @key_definition}
                ),
                Schema.field("attestation_hints",
                  required?: true,
                  types: [:array],
                  cardinality: {0, 16},
                  nested: {:array, @hint_definition}
                ),
                Schema.field("extensions", required?: true, types: [:object]),
                Schema.field("effective_from", required?: true, types: [:string])
              ])

  @doc "Decode and structurally validate one canonical descriptor envelope."
  @spec decode(term(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def decode(compact, %Limits{} = limits) do
    with {:ok, envelope} <- CompactJws.parse(compact, "cap+party", limits),
         {:ok, payload} <- Schema.validate(@definition, envelope.payload) do
      extract(payload, envelope)
    end
  end

  def decode(_compact, _limits), do: {:error, Error.new(:invalid_type, ["limits"])}

  @doc "Return the descriptor's domain-separated content digest."
  @spec digest(t()) :: binary()
  def digest(%__MODULE__{envelope: %CompactJws{payload_bytes: bytes}}),
    do: :party_descriptor_content |> Digest.hash(bytes) |> Digest.to_tagged()

  @doc "Verify one descriptor at genesis or against an already verified predecessor."
  @spec verify(term(), nil | DescriptorFacts.t(), Limits.t()) ::
          {:ok, DescriptorFacts.t()} | {:error, Error.t()}
  def verify(compact, predecessor, %Limits{} = limits) do
    with {:ok, verified_predecessor} <- verify_predecessor(predecessor, limits),
         {:ok, descriptor} <- decode(compact, limits),
         {:ok, party_id, public_key, lineage} <-
           verification_context(descriptor, verified_predecessor, compact),
         :ok <- CompactJws.verify_signature(descriptor.envelope, public_key) do
      {:ok, facts(descriptor, party_id, lineage)}
    end
  end

  def verify(_compact, _predecessor, _limits),
    do: {:error, Error.new(:invalid_type, ["limits"])}

  defp extract({:object, members}, envelope) do
    values = Map.new(members)
    {:string, effective_from_value} = values["effective_from"]
    {:integer, descriptor_number} = values["descriptor_number"]

    with {:ok, party_id} <- optional_digest(values, "party_id"),
         {:ok, previous} <- optional_digest(values, "prev_descriptor_digest"),
         {:ok, keys} <- verification_keys(values["verification_keys"]),
         :ok <- unique_active_keys(keys),
         {:ok, hints} <- attestation_hints(values["attestation_hints"]),
         :ok <- valid_extensions(values["extensions"]),
         {:ok, effective_from} <- Timestamp.parse(effective_from_value),
         :ok <- genesis_shape(descriptor_number, party_id, previous) do
      {:ok,
       %__MODULE__{
         protocol_revision: 1,
         party_id: party_id,
         descriptor_number: descriptor_number,
         prev_descriptor_digest: previous,
         verification_keys: keys,
         attestation_hints: hints,
         extensions: values["extensions"],
         effective_from: effective_from,
         envelope: envelope
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp verification_keys({:array, values}) do
    Enum.reduce_while(values, {:ok, []}, fn {:object, members}, {:ok, keys} ->
      value = Map.new(members)

      with {:string, key_id} <- value["key_id"],
           {:string, "Ed25519"} <- value["algorithm"],
           {:string, encoded} <- value["public_key"],
           {:ok, <<_::256>> = public_key} <- Base64Url.decode(encoded),
           {:ok, status} <- key_status(value["status"]) do
        key = %VerificationKey{
          key_id: key_id,
          algorithm: :ed25519,
          public_key: public_key,
          status: status
        }

        {:cont, {:ok, [key | keys]}}
      else
        _failure -> {:halt, descriptor_error()}
      end
    end)
    |> reverse_keys()
  end

  defp reverse_keys({:ok, keys}), do: {:ok, Enum.reverse(keys)}
  defp reverse_keys({:error, %Error{}} = error), do: error

  defp key_status({:string, "active"}), do: {:ok, :active}
  defp key_status({:string, "retired"}), do: {:ok, :retired}

  defp unique_active_keys(keys) do
    key_ids = Enum.map(keys, & &1.key_id)

    if key_ids == Enum.uniq(key_ids) and Enum.any?(keys, &(&1.status == :active)),
      do: :ok,
      else: descriptor_error()
  end

  defp attestation_hints({:array, values}) do
    {:ok,
     Enum.map(values, fn {:object, members} ->
       value = Map.new(members)
       {:string, kind} = value["kind"]
       {:string, uri} = value["uri"]
       %AttestationHint{kind: kind, uri: uri}
     end)}
  end

  defp valid_extensions({:object, members}) do
    case Map.new(members) do
      %{"critical" => {:object, _}, "optional" => {:object, _}} when length(members) == 2 -> :ok
      _value -> descriptor_error()
    end
  end

  defp optional_digest(values, name) do
    case Map.fetch(values, name) do
      :error ->
        {:ok, nil}

      {:ok, {:string, tagged}} ->
        case Digest.from_tagged(tagged) do
          {:ok, _digest} -> {:ok, tagged}
          _error -> descriptor_error()
        end
    end
  end

  defp genesis_shape(1, nil, nil), do: :ok

  defp genesis_shape(number, party_id, previous)
       when number > 1 and is_binary(party_id) and is_binary(previous),
       do: :ok

  defp genesis_shape(_number, _party_id, _previous), do: descriptor_error()

  defp verify_predecessor(nil, _limits), do: {:ok, nil}

  defp verify_predecessor(%DescriptorFacts{lineage: lineage} = supplied, limits)
       when is_list(lineage) and lineage != [] do
    with {:ok, verified} <- verify_lineage(lineage, limits),
         true <- verified.descriptor_digest == supplied.descriptor_digest do
      {:ok, verified}
    else
      _failure -> chain_error()
    end
  end

  defp verify_predecessor(_predecessor, _limits), do: chain_error()

  defp verify_lineage([genesis | rest], limits) do
    with {:ok, first} <- verify_one(genesis, nil, limits) do
      Enum.reduce_while(rest, {:ok, first}, &verify_lineage_member(&1, &2, limits))
    end
  end

  defp verify_lineage_member(compact, {:ok, predecessor}, limits) do
    case verify_one(compact, predecessor, limits) do
      {:ok, next} -> {:cont, {:ok, next}}
      error -> {:halt, error}
    end
  end

  defp verify_one(compact, predecessor, limits) do
    with {:ok, descriptor} <- decode(compact, limits),
         {:ok, party_id, public_key, lineage} <-
           verification_context(descriptor, predecessor, compact),
         :ok <- CompactJws.verify_signature(descriptor.envelope, public_key) do
      {:ok, facts(descriptor, party_id, lineage)}
    end
  end

  defp verification_context(%__MODULE__{descriptor_number: 1} = descriptor, nil, compact) do
    with {:ok, key} <- active_key(descriptor.verification_keys, descriptor.envelope.kid) do
      {:ok, digest(descriptor), key.public_key, [compact]}
    end
  end

  defp verification_context(%__MODULE__{descriptor_number: 1}, _predecessor, _compact),
    do: chain_error()

  defp verification_context(%__MODULE__{} = descriptor, %DescriptorFacts{} = predecessor, compact) do
    expected_number = predecessor.descriptor_number + 1

    if descriptor.descriptor_number == expected_number and
         descriptor.prev_descriptor_digest == predecessor.descriptor_digest and
         descriptor.party_id == predecessor.party_id do
      with {:ok, key} <-
             active_key(predecessor.descriptor.verification_keys, descriptor.envelope.kid) do
        {:ok, predecessor.party_id, key.public_key, predecessor.lineage ++ [compact]}
      end
    else
      chain_error()
    end
  end

  defp verification_context(_descriptor, _predecessor, _compact), do: chain_error()

  defp active_key(keys, kid) do
    case Enum.find(keys, &(&1.key_id == kid and &1.status == :active)) do
      %VerificationKey{} = key -> {:ok, key}
      nil -> key_error()
    end
  end

  defp facts(descriptor, party_id, lineage) do
    %DescriptorFacts{
      descriptor: descriptor,
      descriptor_digest: digest(descriptor),
      party_id: party_id,
      descriptor_number: descriptor.descriptor_number,
      prev_descriptor_digest: descriptor.prev_descriptor_digest,
      signing_key_id: descriptor.envelope.kid,
      descriptor_position: :head,
      lineage: lineage
    }
  end

  defp descriptor_error,
    do: {:error, Error.new(:descriptor_invalid, ["party_descriptor"])}

  defp key_error,
    do: {:error, Error.new(:descriptor_key_invalid, ["party_descriptor", "verification_keys"])}

  defp chain_error,
    do: {:error, Error.new(:descriptor_chain_invalid, ["party_descriptor", "chain"])}
end
