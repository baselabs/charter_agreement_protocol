defmodule CharterAgreementProtocol.ChainFixture do
  @moduledoc false

  alias CharterAgreementProtocol.{
    AcceptanceFixture,
    CharterRevisionFixture,
    DescriptorFixture,
    TerminationFixture
  }

  def base do
    issuer = DescriptorFixture.genesis()
    acceptor = DescriptorFixture.genesis(key: DescriptorFixture.key(2, "acceptor-key"))

    genesis =
      CharterRevisionFixture.genesis(
        claims: %{
          "parties" => [
            %{"party_descriptor_digest" => issuer.digest, "role" => "issuer"},
            %{"party_descriptor_digest" => acceptor.digest, "role" => "acceptor"}
          ]
        }
      )

    %{issuer: issuer, acceptor: acceptor, genesis: genesis}
  end

  def successor(predecessor, number, options \\ []) do
    claims =
      options
      |> Keyword.get(:claims, %{})
      |> Map.put_new("parties", predecessor.claims["parties"])

    CharterRevisionFixture.successor(predecessor, number, Keyword.put(options, :claims, claims))
  end

  def dual_acceptances(revision, setup) do
    [
      acceptance(revision, setup.issuer, "issuer"),
      acceptance(revision, setup.acceptor, "acceptor")
    ]
  end

  def acceptance(revision, descriptor, role) do
    revision
    |> AcceptanceFixture.claims(descriptor, role)
    |> AcceptanceFixture.compact(descriptor)
  end

  def termination(revision, descriptor, role, overrides \\ %{}) do
    revision
    |> TerminationFixture.claims(descriptor, role, overrides)
    |> TerminationFixture.compact(descriptor)
  end

  def descriptors(setup), do: [setup.issuer.compact, setup.acceptor.compact]
end
