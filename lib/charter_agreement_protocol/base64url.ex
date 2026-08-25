defmodule CharterAgreementProtocol.Base64Url do
  @moduledoc """
  CAP never authorizes.

  Strict unpadded base64url over the RFC 4648 URL-safe alphabet.

  Decoding rejects padding, non-alphabet bytes, impossible lengths, and
  alternate spellings with non-zero pad bits by decode→re-encode comparison.
  """

  alias CharterAgreementProtocol.Error

  @alphabet ~r/\A[A-Za-z0-9_-]*\z/

  @doc "Encode bytes as canonical unpadded base64url."
  @spec encode(binary()) :: binary()
  def encode(data) when is_binary(data), do: Base.url_encode64(data, padding: false)

  @doc "Decode canonical unpadded base64url."
  @spec decode(term()) :: {:ok, binary()} | {:error, Error.t()}
  def decode(input) when is_binary(input) do
    cond do
      String.contains?(input, "=") ->
        {:error, Error.new(:base64url_padded, ["base64url"])}

      not Regex.match?(@alphabet, input) ->
        {:error, Error.new(:base64url_invalid, ["base64url"])}

      true ->
        decode_canonical(input)
    end
  end

  def decode(_input), do: {:error, Error.new(:invalid_type, ["base64url"])}

  defp decode_canonical(input) do
    case Base.url_decode64(input, padding: false) do
      {:ok, bytes} ->
        if encode(bytes) == input,
          do: {:ok, bytes},
          else: {:error, Error.new(:base64url_invalid, ["base64url"])}

      _error ->
        {:error, Error.new(:base64url_invalid, ["base64url"])}
    end
  end
end
