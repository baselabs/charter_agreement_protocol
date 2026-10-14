defmodule CharterAgreementProtocol.ChainCostTest do
  use ExUnit.Case, async: false

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    Capability,
    CryptoTrace,
    Digest,
    Error,
    Internal.Retained,
    Limits,
    Signature,
    SigningFixture
  }

  test "repeated and late failing acceptance sets check each signature once with no pure exponentiation" do
    world = SigningFixture.world("Ed25519")
    Capability.kat_verifies?("Ed25519")

    {lineage, _last} =
      Enum.map_reduce(2..24, world.issuer.digest, fn number, previous ->
        claims =
          Map.merge(world.issuer.claims, %{
            "descriptor_number" => number,
            "party_id" => world.issuer.digest,
            "prev_descriptor_digest" => previous
          })

        compact = SigningFixture.compact(:party_descriptor, claims, world.issuer)

        digest =
          :party_descriptor_content
          |> Digest.hash(SigningFixture.canonical(claims))
          |> Digest.to_tagged()

        {compact, digest}
      end)

    for count <- [2, 40], fail_last <- [false, true] do
      acceptances =
        for second <- 1..count do
          claims =
            Map.put(
              world.claims.acceptance,
              "accepted_at",
              "2026-08-25T11:00:#{String.pad_leading(to_string(second), 2, "0")}Z"
            )

          SigningFixture.compact(:acceptance, claims, world.issuer)
        end

      acceptances =
        if fail_last do
          List.update_at(acceptances, -1, fn compact ->
            [header, payload, encoded] = String.split(compact, ".")

            <<r::binary-size(32), first, rest::binary>> =
              Base.url_decode64!(encoded, padding: false)

            encoded = Base.url_encode64(r <> <<Bitwise.bxor(first, 1)>> <> rest, padding: false)
            header <> "." <> payload <> "." <> encoded
          end)
        else
          acceptances
        end

      operation = fn ->
        CAP.verify_chain(
          world.set.revisions,
          acceptances,
          world.set.descriptors ++ lineage,
          [],
          Limits.default()
        )
      end

      {result, calls} = CryptoTrace.count(:verify, operation)
      assert length(calls) == 25 + count

      if fail_last,
        do: assert(match?({:error, %Error{code: :signature_invalid}}, result)),
        else: assert(match?({:error, %Error{code: :chain_invalid}}, result))

      {^result, pure_calls} = CryptoTrace.count(Signature, :power_fallback, 3, operation)
      assert pure_calls == []
    end
  end

  test "mixed retained records compare each shape once" do
    world = SigningFixture.world("Ed25519")

    {:ok, facts} =
      CAP.verify_chain(
        world.set.revisions,
        world.set.acceptances,
        world.set.descriptors,
        [],
        Limits.default()
      )

    n = 80
    supplied = List.duplicate(~U[2026-10-13 00:00:00Z], n)
    models = List.duplicate(hd(facts.acceptance_facts), n) ++ [hd(supplied)]

    {true, calls} =
      CryptoTrace.count(Retained, :compatible?, 2, fn ->
        Retained.compatible?(supplied, models)
      end)

    assert length(calls) < n * 40
  end

  test "set termination verification checks each descriptor signature once" do
    world = SigningFixture.world("Ed25519")
    Capability.kat_verifies?("Ed25519")
    termination = SigningFixture.compact(:termination, world.claims.termination, world.issuer)

    {{:ok, _facts}, calls} =
      CryptoTrace.count(:verify, fn ->
        CAP.verify_chain(
          world.set.revisions,
          world.set.acceptances,
          world.set.descriptors,
          List.duplicate(termination, 40),
          Limits.default()
        )
      end)

    assert length(calls) == 2 + 2 + 40
  end
end
