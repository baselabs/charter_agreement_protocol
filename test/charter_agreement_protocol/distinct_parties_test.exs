defmodule CharterAgreementProtocol.DistinctPartiesTest do
  @moduledoc """
  A charter's parties are distinct parties: a revision may not name one
  descriptor for two roles, a revision's parties must resolve to different
  descriptor histories, and a chain view holds exactly the histories its
  revisions name. Before 0.5.0 a single party could satisfy "every party
  accepted" by holding both roles while an unrelated history sat in the view.
  """
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    ChainFixture,
    CharterRevisionFixture,
    DescriptorFixture,
    Error,
    Limits
  }

  defp revision(parties) do
    CharterRevisionFixture.genesis(
      claims: %{
        "parties" =>
          Enum.map(parties, fn {descriptor, role} ->
            %{"party_descriptor_digest" => descriptor.digest, "role" => role}
          end)
      }
    )
  end

  defp acceptances(revision, parties) do
    Enum.map(parties, fn {descriptor, role} ->
      ChainFixture.acceptance(revision, descriptor, role).compact
    end)
  end

  setup do
    party = DescriptorFixture.genesis()
    other = DescriptorFixture.genesis(key: DescriptorFixture.key(2, "acceptor-key"))
    %{party: party, other: other}
  end

  test "a revision naming one descriptor for both roles rejects at decode", %{party: party} do
    shared = revision([{party, "issuer"}, {party, "acceptor"}])

    assert {:error, %Error{code: :revision_invalid}} =
             CAP.decode_charter_revision(shared.bytes, Limits.default())
  end

  test "one party cannot accept for both roles with an unrelated history in the view",
       %{party: party, other: other} do
    successor = DescriptorFixture.successor(party, 2)
    parties = [{party, "issuer"}, {successor, "acceptor"}]
    rev = revision(parties)

    assert {:error, %Error{code: :chain_invalid}} =
             CAP.verify_chain(
               [rev.bytes],
               acceptances(rev, parties),
               [party.compact, successor.compact, other.compact],
               [],
               Limits.default()
             )
  end

  test "a history no revision names rejects the view", %{party: party, other: other} do
    third = DescriptorFixture.genesis(key: DescriptorFixture.key(3, "third-key"))
    parties = [{party, "issuer"}, {other, "acceptor"}]
    rev = revision(parties)

    assert {:error, %Error{code: :chain_invalid}} =
             CAP.verify_chain(
               [rev.bytes],
               acceptances(rev, parties),
               [party.compact, other.compact, third.compact],
               [],
               Limits.default()
             )
  end

  test "two distinct parties with exactly their histories still verify",
       %{party: party, other: other} do
    parties = [{party, "issuer"}, {other, "acceptor"}]
    rev = revision(parties)

    assert {:ok, facts} =
             CAP.verify_chain(
               [rev.bytes],
               acceptances(rev, parties),
               [party.compact, other.compact],
               [],
               Limits.default()
             )

    assert facts.accepted_revision_digests == [rev.digest]
  end
end
