defmodule CharterAgreementProtocol.ConformanceFixtureKeys do
  @moduledoc false

  @scope_seed_bytes %{"issuer" => 1, "restricted" => 2, "acceptor" => 3, "successor" => 4}

  # The canonical test corpus uses public, repeated-byte Ed25519 fixture seeds.
  def ed25519(byte), do: :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32))

  def scope_ed25519(kid), do: ed25519(Map.fetch!(@scope_seed_bytes, kid))

  def legacy_ed25519_private(public) do
    Enum.find_value(1..9, fn byte ->
      {candidate, private} = ed25519(byte)
      if candidate == public, do: private
    end)
  end
end
