defmodule CharterAgreementProtocol.Internal.Retained do
  @moduledoc "Retained byte extraction for re-verification. CAP never authorizes."

  alias CharterAgreementProtocol.{Base64Url, CompactJws}

  @spec list?(term()) :: boolean()
  def list?([]), do: true
  def list?([_item | rest]), do: list?(rest)
  def list?(_other), do: false

  @spec binaries?(term()) :: boolean()
  def binaries?([]), do: true
  def binaries?([item | rest]) when is_binary(item), do: binaries?(rest)
  def binaries?(_other), do: false

  @spec compact(term()) :: {:ok, binary()} | :error
  def compact(%CompactJws{message: message, signature: signature})
      when is_binary(message) and is_binary(signature),
      do: {:ok, message <> "." <> Base64Url.encode(signature)}

  def compact(_other), do: :error
  @spec compatible?(term(), term()) :: boolean()
  def compatible?(%{__struct__: module} = supplied, %{__struct__: module} = verified) do
    Map.keys(supplied) == Map.keys(verified) and
      Enum.all?(Map.from_struct(verified), fn {field, value} ->
        optional_scalar?(module, field, Map.get(supplied, field)) or
          field_shape?(field, Map.get(supplied, field), value)
      end)
  end

  def compatible?(supplied, verified) when is_binary(verified), do: is_binary(supplied)
  def compatible?(supplied, verified) when is_integer(verified), do: is_integer(supplied)
  def compatible?(supplied, verified) when is_float(verified), do: is_float(supplied)
  def compatible?(supplied, nil), do: is_nil(supplied)
  def compatible?(supplied, verified) when is_boolean(verified), do: is_boolean(supplied)
  def compatible?(supplied, verified) when is_atom(verified), do: is_atom(supplied)

  def compatible?(supplied, verified) when is_list(verified) do
    list?(supplied) and list?(verified) and
      Enum.all?(supplied, fn item -> Enum.any?(verified, &compatible?(item, &1)) end)
  end

  def compatible?(supplied, verified) when is_tuple(verified) do
    is_tuple(supplied) and tuple_size(supplied) == tuple_size(verified) and
      Enum.all?(Enum.zip(Tuple.to_list(supplied), Tuple.to_list(verified)), fn {value, model} ->
        compatible?(value, model)
      end)
  end

  def compatible?(_supplied, _verified), do: false

  defp optional_scalar?(module, field, nil) when field in [:alg, :protocol_revision],
    do:
      module in [
        CharterAgreementProtocol.DescriptorFacts,
        CharterAgreementProtocol.AcceptanceFacts,
        CharterAgreementProtocol.TerminationFacts,
        CharterAgreementProtocol.RevisionFacts
      ]

  defp optional_scalar?(_module, _field, _value), do: false

  defp field_shape?(field, supplied, _verified)
       when field in [
              :lineage,
              :optional_extensions_retained,
              :accepted_revision_digests,
              :superseded_revision_digests,
              :supersedes,
              :reason_codes,
              :sibling_descriptors,
              :revision_digests,
              :acceptance_digests
            ],
       do: binaries?(supplied)

  defp field_shape?(:not_verified, supplied, _verified),
    do: list?(supplied) and Enum.all?(supplied, &is_atom/1)

  defp field_shape?(:chain_topology, supplied, _verified), do: supplied in [:linear, :forked]
  defp field_shape?(:topology, supplied, _verified), do: supplied in [:linear, :forked]

  defp field_shape?(:descriptor_position, supplied, _verified),
    do: supplied in [:head, :superseded, :contested]

  defp field_shape?(field, supplied, nil)
       when field in [
              :charter_id,
              :party_id,
              :prev_revision_digest,
              :prev_descriptor_digest,
              :uri_hint,
              :detail_digest
            ],
       do: is_nil(supplied) or is_binary(supplied)

  defp field_shape?(:effective_until, supplied, nil),
    do: is_nil(supplied) or is_struct(supplied, DateTime)

  defp field_shape?(_field, supplied, verified), do: compatible?(supplied, verified)
end
