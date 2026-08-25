defmodule CharterAgreementProtocol.CompactJws do
  @moduledoc """
  CAP never authorizes.

  Bounded parser and verifier for attached compact JWS envelopes.

  The parser accepts only canonical protected-header and payload bytes. A key
  identifier remains an untrusted hint until an artifact verifier resolves it
  against its caller-supplied verification context.
  """

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Error, Json, Limits, Signature}

  @enforce_keys [
    :kid,
    :typ,
    :protected_segment,
    :payload_segment,
    :message,
    :signature,
    :payload,
    :payload_bytes
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          kid: binary(),
          typ: binary(),
          protected_segment: binary(),
          payload_segment: binary(),
          message: binary(),
          signature: <<_::512>>,
          payload: Json.value(),
          payload_bytes: binary()
        }

  @doc "Parse one canonical attached compact JWS under caller bounds."
  @spec parse(term(), binary(), Limits.t()) :: {:ok, t()} | {:error, Error.t()}
  def parse(compact, expected_typ, %Limits{} = limits)
      when is_binary(compact) and is_binary(expected_typ) do
    cond do
      not Limits.valid?(limits) ->
        {:error, Error.new(:invalid_limits, ["limits"])}

      byte_size(compact) > limits.max_bytes ->
        {:error, Error.new(:limit_exceeded, ["compact_jws", "bytes"])}

      true ->
        parse_segments(compact, expected_typ, limits)
    end
  end

  def parse(_compact, _expected_typ, %Limits{} = limits) do
    if Limits.valid?(limits),
      do: {:error, Error.new(:invalid_type, ["compact_jws"])},
      else: {:error, Error.new(:invalid_limits, ["limits"])}
  end

  def parse(_compact, _expected_typ, _limits),
    do: {:error, Error.new(:invalid_type, ["limits"])}

  @doc "Verify the envelope signature with one exact raw Ed25519 public key."
  @spec verify_signature(t(), term()) :: :ok | {:error, Error.t()}
  def verify_signature(%__MODULE__{} = envelope, public_key),
    do: Signature.verify(envelope.message, envelope.signature, public_key)

  def verify_signature(_envelope, _public_key), do: signature_error()

  defp parse_segments(compact, expected_typ, limits) do
    case :binary.split(compact, ".", [:global]) do
      [protected_segment, payload_segment, signature_segment] ->
        with {:ok, protected_bytes} <- decode_segment(protected_segment),
             {:ok, payload_bytes} <- decode_segment(payload_segment),
             {:ok, signature} <- decode_signature(signature_segment),
             {:ok, protected} <- canonical_value(protected_bytes, limits, :protected),
             {:ok, kid} <- protected_header(protected, expected_typ),
             {:ok, payload} <- canonical_value(payload_bytes, limits, :payload) do
          {:ok,
           %__MODULE__{
             kid: kid,
             typ: expected_typ,
             protected_segment: protected_segment,
             payload_segment: payload_segment,
             message: protected_segment <> "." <> payload_segment,
             signature: signature,
             payload: payload,
             payload_bytes: payload_bytes
           }}
        end

      _segments ->
        compact_error()
    end
  end

  defp decode_segment(segment) do
    case Base64Url.decode(segment) do
      {:ok, bytes} -> {:ok, bytes}
      _error -> compact_error()
    end
  end

  defp decode_signature(segment) do
    case Base64Url.decode(segment) do
      {:ok, <<_::512>> = signature} -> {:ok, signature}
      _error -> signature_error()
    end
  end

  defp canonical_value(bytes, limits, kind) do
    with {:ok, value} <- Json.decode(bytes, limits),
         {:ok, canonical} <- Canonicalization.encode(value),
         true <- canonical == bytes do
      {:ok, value}
    else
      _failure -> canonical_error(kind)
    end
  end

  defp protected_header({:object, members}, expected_typ) do
    case Map.new(members) do
      %{
        "alg" => {:string, "EdDSA"},
        "kid" => {:string, kid},
        "typ" => {:string, ^expected_typ}
      }
      when length(members) == 3 ->
        if valid_kid?(kid), do: {:ok, kid}, else: protected_error()

      _header ->
        protected_error()
    end
  end

  defp protected_header(_value, _expected_typ), do: protected_error()

  defp valid_kid?(kid) when is_binary(kid) and byte_size(kid) in 1..128,
    do: kid_bytes?(kid)

  defp valid_kid?(_kid), do: false
  defp kid_bytes?(<<>>), do: true

  defp kid_bytes?(<<byte, rest::binary>>)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?-, ?., ?_, ?~],
       do: kid_bytes?(rest)

  defp kid_bytes?(_bytes), do: false

  defp compact_error, do: {:error, Error.new(:compact_invalid, ["compact_jws"])}

  defp canonical_error(:protected),
    do: {:error, Error.new(:protected_header_invalid, ["compact_jws", "protected"])}

  defp canonical_error(:payload),
    do: {:error, Error.new(:non_canonical_bytes, ["compact_jws", "payload"])}

  defp protected_error,
    do: {:error, Error.new(:protected_header_invalid, ["compact_jws", "protected"])}

  defp signature_error,
    do: {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}
end
