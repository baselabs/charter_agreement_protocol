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
end
