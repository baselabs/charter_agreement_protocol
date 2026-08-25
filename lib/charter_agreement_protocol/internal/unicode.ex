defmodule CharterAgreementProtocol.Internal.Unicode do
  @moduledoc false

  @doc false
  @spec ijson_string?(binary()) :: boolean()
  def ijson_string?(value) when is_binary(value),
    do: String.valid?(value) and interoperable_codepoints?(value)

  defp interoperable_codepoints?(<<codepoint::utf8, rest::binary>>) do
    not noncharacter?(codepoint) and interoperable_codepoints?(rest)
  end

  defp interoperable_codepoints?(<<>>), do: true

  defp noncharacter?(codepoint) when codepoint in 0xFDD0..0xFDEF, do: true
  defp noncharacter?(codepoint), do: rem(codepoint, 0x10000) in [0xFFFE, 0xFFFF]
end
