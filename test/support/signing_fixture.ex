defmodule CharterAgreementProtocol.SigningFixture do
  @moduledoc false
  alias CharterAgreementProtocol.{
    AcceptanceFixture,
    ArtifactSet,
    Base64Url,
    Canonicalization,
    ChainFixture,
    Digest,
    ReceiptFixture,
    TerminationFixture
  }

  def world(algorithm) do
    template = ChainFixture.base()
    issuer = descriptor(template.issuer.claims, algorithm, 1, "issuer-key")
    acceptor = descriptor(template.acceptor.claims, algorithm, 2, "acceptor-key")

    claims =
      Map.merge(template.genesis.claims, %{
        "protocol_revision" => 2,
        "parties" => [
          %{"party_descriptor_digest" => issuer.digest, "role" => "issuer"},
          %{"party_descriptor_digest" => acceptor.digest, "role" => "acceptor"}
        ]
      })

    bytes = canonical(claims)
    digest = content(:charter_revision_content, bytes)
    revision = %{claims: claims, bytes: bytes, digest: digest, charter_id: digest}
    a = AcceptanceFixture.claims(revision, issuer, "issuer") |> mint_revision(algorithm)
    b = AcceptanceFixture.claims(revision, acceptor, "acceptor") |> mint_revision(algorithm)

    {:ok, set} =
      ArtifactSet.build(
        [bytes],
        [compact(:acceptance, a, issuer), compact(:acceptance, b, acceptor)],
        [],
        [issuer.compact, acceptor.compact]
      )

    %{
      issuer: issuer,
      acceptor: acceptor,
      revision: revision,
      set: set,
      claims: %{
        party_descriptor: issuer.claims,
        acceptance: a,
        termination:
          TerminationFixture.claims(revision, issuer, "issuer") |> mint_revision(algorithm),
        receipt: ReceiptFixture.claims(revision) |> mint_revision(algorithm)
      }
    }
  end

  def input(world, kind),
    do: %{
      "kid" => world.issuer.kid,
      "claims" => world.claims[kind],
      "algorithm" => world.issuer.algorithm,
      "public_key" => world.issuer.public
    }

  def sign(message, %{algorithm: "Ed25519", private: private}),
    do: :crypto.sign(:eddsa, :none, message, [private, :ed25519])

  def sign(message, %{algorithm: "ML-DSA-65", private: private}),
    do: :crypto.sign(:mldsa65, :none, message, {:expandedkey, private})

  def compact(kind, claims, descriptor) do
    typ =
      %{
        party_descriptor: "cap+party",
        acceptance: "cap+acceptance",
        termination: "cap+termination",
        receipt: "cap+receipt"
      }[kind]

    message =
      Base64Url.encode(
        canonical(%{"alg" => descriptor.algorithm, "kid" => descriptor.kid, "typ" => typ})
      ) <> "." <> Base64Url.encode(canonical(claims))

    message <> "." <> Base64Url.encode(sign(message, descriptor))
  end

  def canonical(claims) do
    {:ok, value} = Canonicalization.from_plain(claims)
    {:ok, bytes} = Canonicalization.encode(value)
    bytes
  end

  defp descriptor(template, algorithm, byte, kid) do
    {public, private} =
      if algorithm == "Ed25519",
        do: :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<byte>>, 32)),
        else: :crypto.generate_key(:mldsa65, [])

    claims =
      template
      |> mint_revision(algorithm)
      |> Map.put("verification_keys", [
        %{
          "key_id" => kid,
          "algorithm" => algorithm,
          "public_key" => Base64Url.encode(public),
          "status" => "active"
        }
      ])

    descriptor = %{
      algorithm: algorithm,
      public: public,
      private: private,
      kid: kid,
      claims: claims,
      digest: content(:party_descriptor_content, canonical(claims))
    }

    Map.put(descriptor, :compact, compact(:party_descriptor, claims, descriptor))
  end

  defp mint_revision(claims, algorithm),
    do: Map.put(claims, "protocol_revision", revision(algorithm))

  defp revision("Ed25519"), do: 2
  defp revision("ML-DSA-65"), do: 3
  defp content(domain, bytes), do: domain |> Digest.hash(bytes) |> Digest.to_tagged()
end
