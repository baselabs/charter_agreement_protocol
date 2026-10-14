# Produce and verify with the signer

In this tutorial two parties, an issuer and an acceptor, form a charter. Each
publishes a [party descriptor](glossary.md), they agree on one charter
[revision](glossary.md), and each signs an [acceptance](glossary.md). Then you
switch sides and verify everything with CAP alone, the way the other party
would.

CAP never signs and never holds a key. Signing is the job of the companion
package [`charter_agreement_signer`](https://hexdocs.pm/charter_agreement_signer).
It asks CAP for the exact bytes to sign, signs them through a key handle you
supply, and verifies the result through CAP before returning it.

Work through [Your first verified charter](getting-started.md) first if you
have not used `verify_chain/5` yet.

## Install

```elixir
def deps do
  [
    {:charter_agreement_protocol, "~> 0.6.0"},
    {:charter_agreement_signer, "~> 0.5.0"}
  ]
end
```

Only the side that signs needs the signer. A party that only verifies depends
on `charter_agreement_protocol` alone.

Run `mix deps.get` and start `iex -S mix`. The blocks below run in order in one
session.

## Write a key handle

The signer never sees a private key. You pass it a key handle, a
`{module, ref}` pair. The module implements two callbacks:

- `key_identity/1` returns the key id and the public key in one call;
- `sign/2` signs the bytes it is given and returns the raw signature.

In production `sign/2` calls your HSM or KMS and `ref` names the key there.
This demo module keeps an Ed25519 key in memory:

```elixir
defmodule DemoKey do
  @behaviour CharterAgreementSigner

  # Demo only. A fixed seed makes the outputs on this page repeatable.
  # Real keys come from your key store, never from a seed in code.
  def handle(kid, seed) do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519, seed)
    {__MODULE__, %{kid: kid, public: public, private: private}}
  end

  @impl true
  def key_identity(%{kid: kid, public: public}), do: {:ok, {kid, public}}

  @impl true
  def sign(message, %{private: private}),
    do: {:ok, :crypto.sign(:eddsa, :none, message, [private, :ed25519])}
end

alias CharterAgreementProtocol, as: CAP

issuer = DemoKey.handle("issuer-key-1", :binary.copy(<<1>>, 32))
acceptor = DemoKey.handle("acceptor-key-1", :binary.copy(<<2>>, 32))
```

## Publish a descriptor for each party

A descriptor pins the public keys a party signs with. Both parties use the
same claim shape, so build it from the handle:

```elixir
descriptor_claims = fn {module, ref} ->
  {:ok, {kid, public_key}} = module.key_identity(ref)

  %{
    "protocol_revision" => 2,
    "descriptor_number" => 1,
    "verification_keys" => [
      %{
        "key_id" => kid,
        "algorithm" => "Ed25519",
        "public_key" => CAP.Base64Url.encode(public_key),
        "status" => "active"
      }
    ],
    "attestation_hints" => [],
    "extensions" => %{"critical" => %{}, "optional" => %{}},
    "effective_from" => "2026-10-01T09:00:00Z"
  }
end

{:ok, %{descriptor: issuer_descriptor}} =
  CharterAgreementSigner.sign_descriptor(descriptor_claims.(issuer), issuer)

{:ok, %{descriptor: acceptor_descriptor}} =
  CharterAgreementSigner.sign_descriptor(descriptor_claims.(acceptor), acceptor)
```

`"protocol_revision" => 2` goes with `Ed25519`, the default. The signer takes
the key id for the signed header from `key_identity/1`, never from the claims.
Each descriptor came back already verified by `CAP.verify_descriptor/3`.

The revision refers to each party by its descriptor's digest:

```elixir
limits = CAP.Limits.default()

descriptor_digest = fn compact ->
  {:ok, descriptor} = CAP.decode_party_descriptor(compact, limits)
  CAP.descriptor_digest(descriptor)
end

issuer_digest = descriptor_digest.(issuer_descriptor)
acceptor_digest = descriptor_digest.(acceptor_descriptor)

{issuer_digest, acceptor_digest}
```

```text
{"sha-256:UmFN7RFO8DhZfE-Px9DTAagN-PYLNjIUkIxuyAhjLL4",
 "sha-256:406Y70xTrD7R5amwdDU2C_GZUeVsmjS4xRd40TZAHXE"}
```

## Write the revision

A revision is the terms, as unsigned canonical JSON. Write it as a plain map
and let `CAP.encode_charter_revision/1` produce the bytes:

```elixir
revision_claims = %{
  "protocol_revision" => 2,
  "revision_number" => 1,
  "parties" => [
    %{"party_descriptor_digest" => issuer_digest, "role" => "issuer"},
    %{"party_descriptor_digest" => acceptor_digest, "role" => "acceptor"}
  ],
  "legal_text" => %{
    "content_digest" =>
      CAP.Digest.hash(:legal_text, "Demo terms\n") |> CAP.Digest.to_tagged(),
    "media_type" => "text/plain"
  },
  "precedence_declaration" => "legal_text_governs",
  "attribution_declaration" => %{"basis" => "legal_text"},
  "effective_from" => "2026-10-01T12:00:00Z",
  "termination_rules" => %{"reason_codes" => ["mutual"]},
  "abp_bindings" => [],
  "receipt_profile" => "com.example.charter/default",
  "extensions" => %{"critical" => %{}, "optional" => %{}}
}

{:ok, revision} = CAP.encode_charter_revision(revision_claims)
```

```text
{:ok,
 "{\"abp_bindings\":[],\"attribution_declaration\":{\"basis\":\"legal_text\"},…}"}
```

The members come out sorted with no whitespace, which is the only spelling CAP
accepts. The legal text itself stays with you: the revision carries its digest.
`encode_charter_revision/1` checks the result with the same decoder verifiers
use, so a bad claims map fails here with the error a verifier would report:

```elixir
CAP.encode_charter_revision(Map.delete(revision_claims, "receipt_profile"))
```

```text
{:error,
 %CharterAgreementProtocol.Error{
   code: :missing_required,
   subject: ["charter_revision", "receipt_profile"],
   detail: nil
 }}
```

Acceptances name the revision by its digest. This is the first revision, so its
digest is also the `charter_id`:

```elixir
{:ok, decoded} = CAP.decode_charter_revision(revision, limits)
revision_digest = CAP.revision_digest(decoded)
```

```text
"sha-256:uVgklHrU2JxmE-Mx8dOrmr1Wk8A2PmM-SxoPSbKMYSc"
```

## Sign both acceptances

Before it signs an acceptance, CAP checks the claims against the artifacts the
signing party holds. Collect them with `CAP.build_set/4`. Its arguments are
revisions, acceptances, terminations, then descriptors:

```elixir
{:ok, view} = CAP.build_set([revision], [], [], [issuer_descriptor, acceptor_descriptor])

acceptance_claims = fn role, party_digest ->
  %{
    "protocol_revision" => 2,
    "charter_id" => revision_digest,
    "revision_number" => 1,
    "revision_digest" => revision_digest,
    "party_descriptor_digest" => party_digest,
    "party_role" => role,
    "accepted_at" => "2026-10-01T13:00:00Z"
  }
end

{:ok, %{acceptance: issuer_acceptance}} =
  CharterAgreementSigner.sign_acceptance(
    acceptance_claims.("issuer", issuer_digest),
    issuer,
    view
  )

{:ok, %{acceptance: acceptor_acceptance}} =
  CharterAgreementSigner.sign_acceptance(
    acceptance_claims.("acceptor", acceptor_digest),
    acceptor,
    view
  )
```

Claims that contradict the view are refused before the key is used. Here the
issuer's key tries to accept in the acceptor's role:

```elixir
CharterAgreementSigner.sign_acceptance(
  acceptance_claims.("acceptor", issuer_digest),
  issuer,
  view
)
```

```text
{:error, {:refused, :signing_refused}}
```

No signature exists after a refusal. The signer's
[error guide](https://hexdocs.pm/charter_agreement_signer/errors.html) lists
its other errors.

## Verify as the counterparty

Now take the other side. The counterparty receives the revision bytes, two
descriptors and two acceptances, and verifies them with CAP only. Note that
`verify_chain/5` takes descriptors before terminations, the reverse of
`build_set/4`:

```elixir
{:ok, facts} =
  CAP.verify_chain(
    [revision],
    [issuer_acceptance, acceptor_acceptance],
    [issuer_descriptor, acceptor_descriptor],
    [],
    limits
  )

facts.accepted_revision_digests
```

```text
["sha-256:uVgklHrU2JxmE-Mx8dOrmr1Wk8A2PmM-SxoPSbKMYSc"]
```

Both acceptances verified against the keys their descriptors pin:

```elixir
for acceptance <- facts.acceptance_facts do
  {acceptance.party_role, acceptance.signing_key_id, acceptance.alg,
   acceptance.protocol_revision}
end
```

```text
[
  {"acceptor", "acceptor-key-1", "Ed25519", 2},
  {"issuer", "issuer-key-1", "Ed25519", 2}
]
```

And the revision governs from its `effective_from`:

```elixir
CAP.governing_revision(facts, ~U[2026-10-02 00:00:00Z])
```

```text
{:ok, "sha-256:uVgklHrU2JxmE-Mx8dOrmr1Wk8A2PmM-SxoPSbKMYSc"}
```

The counterparty reached the same digest the signers computed, from the bytes
alone. Store those bytes: they are the record, and anyone can verify them again
later.

To sign with ML-DSA-65 instead, use an ML-DSA-65 key (listed in the descriptor
with `"algorithm" => "ML-DSA-65"`), pass `algorithm: "ML-DSA-65"` to each signer
call, and set `"protocol_revision" => 3` in the descriptor and acceptance
claims.

## Sign with your own code

The signer is one way to sign. To sign with your own code, for example inside an HSM
client, ask CAP for a plan first. `prepare_signing/5` checks the claims, the context,
your limits and profile, and that the public key is one your own descriptor names,
all before a signature exists. Sign the plan's message, then `finish_signing/2`
assembles the compact and verifies it:

```elixir
alias CharterAgreementProtocol.Capability.Profile

{DemoKey, issuer_ref} = issuer
{:ok, {kid, public_key}} = DemoKey.key_identity(issuer_ref)
claims = acceptance_claims.("issuer", issuer_digest)

{:ok, plan} =
  CAP.prepare_signing(
    :acceptance,
    %{"kid" => kid, "claims" => claims, "public_key" => public_key},
    view,
    limits,
    Profile.full()
  )

{:ok, signature} = DemoKey.sign(plan.signing_input.message, issuer_ref)
{:ok, compact} = CAP.finish_signing(plan, signature)

compact == issuer_acceptance
```

```text
true
```

Ed25519 signing is deterministic, so this is the same acceptance the signer made. A key
that your descriptor does not name is refused before anything is signed:

```elixir
{DemoKey, acceptor_ref} = acceptor
{:ok, {_kid, other_public_key}} = DemoKey.key_identity(acceptor_ref)

{:error, error} =
  CAP.prepare_signing(
    :acceptance,
    %{"kid" => kid, "claims" => claims, "public_key" => other_public_key},
    view,
    limits,
    Profile.full()
  )

error.code
```

```text
:signing_key_mismatch
```

The context depends on the kind: an `ArtifactSet` from `build_set/4` for an acceptance
or a termination, `nil` or the predecessor's facts for a descriptor, and `ChainFacts`
or a `CharterRevision` for a receipt. Limits cover every byte CAP reads, including
the whole set. Your profile covers the revision, your own descriptor history and the
new artifact; the rest of the set is checked under the full profile. Keep the plan as
returned and pass it to `finish_signing/2` unchanged.
The older `*_signing_input` functions and `assemble_compact/2` still work, under
default limits and without the key check.

## Next

- [Integrate CAP into an application](integration.md): what to call at boot,
  limits, what to store, and verifying after you produce.
- [Recipes](recipes.md): receipts, key rotation and other tasks.
- [Verification semantics](verification.md): forks, supersession and contested
  views.
- The signer's [documentation](https://hexdocs.pm/charter_agreement_signer)
  covers `sign_termination/4` and `sign_receipt/4`, and its recipes show HSM
  and KMS key handles.
