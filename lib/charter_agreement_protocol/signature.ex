defmodule CharterAgreementProtocol.Signature do
  @moduledoc """
  Raw Ed25519 verification boundary for already-framed protocol bytes.

  This module accepts only public verification material. It never signs,
  selects trust, or authorizes an artifact.
  """

  alias CharterAgreementProtocol.Error

  @doc "Verify one exact message and raw 64-byte signature with a raw Ed25519 public key."
  @spec verify(term(), term(), term()) :: :ok | {:error, Error.t()}
  def verify(message, <<_::512>> = signature, <<_::256>> = public_key) when is_binary(message) do
    if :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519]),
      do: :ok,
      else: invalid()
  end

  def verify(_message, _signature, _public_key), do: invalid()

  defp invalid, do: {:error, Error.new(:signature_invalid, ["compact_jws", "signature"])}
end
