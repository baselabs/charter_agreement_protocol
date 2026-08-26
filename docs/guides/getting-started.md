# Getting started

Five minutes from install to your first verified artifact evidence.

## Requirements

- Elixir ~> 1.20 (Erlang/OTP 28 or newer recommended; only OTP `:crypto` is used)
- Node 24+ only if you run the repository-side TypeScript verifier yourself —
  it is not needed to use the package
- No runtime dependencies: the package is OTP-crypto-only

## Install

Until the package is published to Hex, depend on the exact remote-durable
commit your CI verified — the same consumption shape any pre-publication
reference consumer uses:

```elixir
def deps do
  [
    {:charter_agreement_protocol,
     git: "https://github.com/baselabs/charter_agreement_protocol.git",
     ref: "f2a6165a4ac58ceb6fca3fd1d0c451b2409ffea6"}
  ]
end
```

Pin an exact `ref`, never a branch: protocol conformance is identity-exact, and
an exact ref is the only durable pre-publication identity. When the package is
published, replace the git dep with an exact Hex requirement and its registry
checksum.

## First contact, in iex

```elixir
iex> alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest, Json, Limits}

iex> Base64Url.encode(<<1, 2, 3>>)
"AQID"

iex> Base64Url.decode("AQID")
{:ok, <<1, 2, 3>>}

iex> Base64Url.decode("AQID=")
{:error, %CharterAgreementProtocol.Error{code: :base64url_padded, subject: ["base64url"], detail: nil}}
```

Padding is rejected; the alphabet is unpadded URL-safe only, and decoding
re-encodes and requires byte-for-byte equality.

Decoding is deterministic and returns a tagged value algebra — there is exactly
one representation per JSON value, so equality is structural:

```elixir
iex> Json.decode("{\"a\":1}")
{:ok, {:object, [{"a", {:integer, 1}}]}}
```

Canonicalization implements RFC 8785 over the tagged algebra. Object members
sort by UTF-16 code units and there is no inter-token whitespace:

```elixir
iex> Canonicalization.encode({:object, [{"z", {:integer, 2}}, {"a", {:integer, 1}}]})
{:ok, "{\"a\":1,\"z\":2}"}

iex> Canonicalization.verify("{\"a\":1}")
{:ok, {:object, [{"a", {:integer, 1}}]}}
```

`Canonicalization.verify/1` accepts received bytes only when re-encoding the
decoded value reproduces them exactly — semantic equivalence is not canonical
equivalence.

Every digest is domain-separated, so the same bytes hash differently per
surface and cross-surface substitution fails:

```elixir
iex> Digest.hash(:legal_text, "hello") |> Digest.to_tagged()
"sha-256:mHsrN6RbGTzM7kj6NhAALPa6rVj4ZI5bBuzdA93x52g"
```

All decode and verification entry points take caller-supplied limits — pure
data, no application config:

```elixir
iex> Limits.default()
%CharterAgreementProtocol.Limits{
  max_bytes: 1048576,
  max_depth: 64,
  max_object_members: 1024,
  max_array_items: 4096,
  max_string_bytes: 65536,
  max_artifact_set_items: 1024
}
```

## Verify the certified corpus from your dependency

The package ships the certified 57-case conformance corpus. The CLI is the sole
filesystem adapter and refuses any corpus whose raw index identity is not the
certified release pin. From a dependent project (the corpus unpacks with the
package under its `priv/conformance`):

```console
$ mix run -e 'CharterAgreementProtocol.Conformance.Cli.run(["--corpus", "deps/charter_agreement_protocol/priv/conformance"])'
```

The returned status is `0` when every certified case recomputed and agreed,
`1` on load or verification failure, and `2` on usage errors. The stdout
report is canonical JSON carrying the corpus digest, registry digest, and raw
index identity. From a repository checkout or an unpacked package directory
the same gate is `mix conformance.verify`, or the escript directly:

```console
$ mix escript.build && ./charter_agreement_protocol --corpus priv/conformance
```

See [Conformance](conformance.md).

## Sign your first evidence (repository demo)

CAP never holds keys. You build a signing input, sign its exact RFC 7515 bytes
with your own Ed25519 key outside CAP, and hand the raw 64-byte signature back
for assembly:

```elixir
{:ok, signing_input} =
  CharterAgreementProtocol.descriptor_signing_input(%{
    "kid" => "issuer-key",
    "claims" => claims
  })

signature = :crypto.sign(:eddsa, :none, signing_input.message, [private_key, :ed25519])
{:ok, compact} = CharterAgreementProtocol.assemble_compact(signing_input, signature)
```

Run the repository's end-to-end demonstration — real Ed25519-signed
descriptors, acceptances, a manufactured same-signer equivocation, a contested
governing view, an action receipt, and a countersigned supersession repair:

```console
$ mix run examples/supplier_fork_demo.exs
equivocation: evidenced
equivocation winner: nil
governing before repair: contested
receipt chain conflict: none
receipt governing match: undetermined
receipt action outcome: effect_committed
repair countersignatures: 2
governing after repair: sha-256:JEgcYljHUCXtsmsg-EW2Tto2VftJVw6OEYJfHByMES0
CAP reports evidence; it does not adjudicate or authorize.
```

## Where to go next

- [Artifacts](artifacts.md) — every artifact's wire shape and claims
- [Verification semantics](verification.md) — forks, contested views,
  supersession, governing computation
- [Receipts](receipts.md) — binding actions to agreements, ABP/BAP identities
- [Recipes](recipes.md) — end-to-end integration patterns
- [Security model](security-model.md) — what verification proves and never
  proves
- The Livebook notebooks under `docs/notebooks` — a runnable charter tour and
  the fork-repair walkthrough
