defmodule CharterAgreementProtocol.DescriptorPublication do
  @moduledoc """
  A bounded, unsigned distribution document for a party's current and next descriptors.
  CAP never authorizes.
  """

  alias CharterAgreementProtocol.{
    Canonicalization,
    Capability.Profile,
    DescriptorPublicationFacts,
    Digest,
    Error,
    Facts,
    Internal.IntegerClaims,
    Json,
    Limits,
    PartyDescriptor,
    Timestamp
  }

  @coordinates ~w(party_id current_descriptor_digest next_descriptor_digest)
  @members Enum.sort(["protocol_revision", "descriptors" | @coordinates])

  @doc "Encode a closed publication using the caller's size and JSON limits."
  @spec encode(term(), Limits.t()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(claims, %Limits{} = limits) do
    cond do
      not Limits.valid?(limits) ->
        {:error, Error.new(:invalid_limits, ["limits"])}

      not is_map(claims) or is_struct(claims) ->
        {:error, Error.new(:invalid_type, ["descriptor_publication"])}

      true ->
        with {:ok, value} <- Canonicalization.from_plain(claims),
             :ok <- IntegerClaims.check(:descriptor_publication, value),
             {:ok, bytes} <- Canonicalization.encode(value),
             {:ok, _document} <- decode(bytes, limits) do
          {:ok, bytes}
        else
          {:error, %Error{code: :limit_exceeded}} = error -> error
          _other -> invalid()
        end
    end
  end

  def encode(_claims, _limits), do: {:error, Error.new(:invalid_type, ["limits"])}

  @doc "Verify the named pair and all signatures and links from genesis."
  @spec verify(term(), Limits.t(), Profile.t()) ::
          {:ok, DescriptorPublicationFacts.t()} | {:error, Error.t()}
  def verify(bytes, %Limits{} = limits, profile) do
    cond do
      not Limits.valid?(limits) -> {:error, Error.new(:invalid_limits, ["limits"])}
      not Profile.valid?(profile) -> {:error, Error.new(:invalid_profile, ["profile"])}
      not is_binary(bytes) -> {:error, Error.new(:invalid_type, ["descriptor_publication"])}
      true -> verify_document(bytes, limits, profile)
    end
  end

  def verify(_bytes, _limits, _profile), do: {:error, Error.new(:invalid_type, ["limits"])}

  @doc "Hash publication bytes under the publication content domain."
  @spec digest(binary()) :: binary()
  def digest(bytes) when is_binary(bytes),
    do: :descriptor_publication_content |> Digest.hash(bytes) |> Digest.to_tagged()

  defp decode(bytes, limits) do
    with {:ok, {:object, fields} = value} <- Json.decode(bytes, limits),
         {:ok, ^bytes} <- Canonicalization.encode(value),
         document = Map.new(fields),
         true <- Enum.sort(Map.keys(document)) == @members,
         {:integer, 8} <- document["protocol_revision"],
         true <- Enum.all?(@coordinates, &coordinate?(document[&1])),
         {:array, items} when length(items) in 2..4096 <- document["descriptors"],
         compacts = for({:string, compact} <- items, do: compact),
         true <- length(compacts) == length(items),
         :ok <- bound_history(compacts, limits) do
      {:ok, Map.put(document, "descriptors", compacts)}
    else
      {:error, %Error{code: :limit_exceeded}} = error -> error
      _other -> invalid()
    end
  end

  defp coordinate?({:string, value}), do: match?({:ok, _digest}, Digest.from_tagged(value))
  defp coordinate?(_other), do: false

  defp bound_history(compacts, limits) do
    if length(compacts) <= limits.max_artifact_set_items and
         Enum.reduce(compacts, 0, &(byte_size(&1) + &2)) <= limits.max_artifact_set_bytes do
      :ok
    else
      {:error, Error.new(:limit_exceeded, ["descriptor_publication", "descriptors"])}
    end
  end

  defp verify_document(bytes, limits, profile) do
    with {:ok, document} <- decode(bytes, limits),
         :ok <- admit(profile),
         {:ok, history} <-
           PartyDescriptor.verify_publication_history(document["descriptors"], limits, profile),
         true <- linear?(history),
         {:ok, current, next} <- select_pair(document, history),
         :lt <-
           Timestamp.compare(current.descriptor.effective_from, next.descriptor.effective_from) do
      Facts.build(DescriptorPublicationFacts, %{
        protocol_revision: 8,
        canonical_bytes: bytes,
        publication_digest: digest(bytes),
        party_id: next.party_id,
        current_descriptor: current,
        next_descriptor: next,
        current_descriptor_digest: current.descriptor_digest,
        next_descriptor_digest: next.descriptor_digest,
        current_effective_from: current.descriptor.effective_from,
        next_effective_from: next.descriptor.effective_from,
        commitment_status:
          if(current.descriptor.next_key_commitment, do: :opened, else: :not_present)
      })
    else
      {:error, %Error{}} = error -> error
      _other -> invalid()
    end
  end

  defp admit(%Profile{revisions: {minimum, maximum}}) when minimum <= 8 and maximum >= 8,
    do: :ok

  defp admit(_profile) do
    {:error,
     Error.new(:revision_outside_profile, ["descriptor_publication", "protocol_revision"])}
  end

  defp linear?([_genesis | successors]) do
    parents = Enum.map(successors, & &1.prev_descriptor_digest)
    parents == Enum.uniq(parents)
  end

  defp select_pair(document, history) do
    {:string, current_digest} = document["current_descriptor_digest"]
    {:string, next_digest} = document["next_descriptor_digest"]
    current = Enum.find(history, &(&1.descriptor_digest == current_digest))
    next = Enum.find(history, &(&1.descriptor_digest == next_digest))

    if current != nil and next != nil and next == List.last(history) and
         document["party_id"] == {:string, next.party_id} and
         next.prev_descriptor_digest == current.descriptor_digest do
      {:ok, current, next}
    else
      invalid()
    end
  end

  defp invalid,
    do: {:error, Error.new(:descriptor_publication_invalid, ["descriptor_publication"])}
end
