# Getting started

Five minutes from install to your first verified artifact evidence.

## Requirements

- Elixir ~> 1.19 (tested lines 1.19.x and 1.20.x); Erlang/OTP 28 or 29, with
  the runtime linked against OpenSSL ≥ 3.5 — the corpus and every ML-DSA
  surface need it (FIPS 204 reached OpenSSL in 3.5.0; a runtime linked against
  OpenSSL 3.0.x cannot generate or verify ML-DSA keys, and OTP 27 exposes no
  ML-DSA algorithms to `:crypto` even with OpenSSL ≥ 3.5 linked). The
  supported-OTP set is asserted in `config/config.exs` and moves in lockstep
  with the Elixir range, `.tool-versions`, and the CI lanes (see
  [the supported-toolchain ADR](../adr/supported-otp-set.md)). Only OTP
  `:crypto` is used.
- Node ≥ 24.8 only if you run the repository-side TypeScript verifier yourself —
  it is not needed to use the package (24.8 is the verifier's declared floor;
  ML-DSA in the Node builtins landed across the 24.6–24.8 minors)
- No runtime dependencies: the package is OTP-crypto-only

## Install

Depend on the published Hex release:

```elixir
def deps do
  [
    {:charter_agreement_protocol, "~> 0.3.0"}
  ]
end
```

Protocol conformance is identity-exact: the published registry
checksum equals the release-candidate gate's archive SHA, so the bytes Hex
serves are the reviewed, certified bytes. Pin the requirement and verify the
shipped corpus from your dependent project (the next sections do exactly
that).

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
  max_artifact_set_items: 1024,
  max_artifact_set_bytes: 67108864
}
```

## Verify the certified corpus from your dependency

The package ships the certified 100-case conformance corpus. The CLI is the sole
filesystem adapter and refuses any corpus whose raw index identity is not the
certified release pin. From a dependent project (the corpus unpacks with the
package under its `priv/conformance`):

```console
$ mix run -e 'System.halt(CharterAgreementProtocol.Conformance.Cli.run(["--corpus", "deps/charter_agreement_protocol/priv/conformance"]))'
```

The process exits `0` when every certified case recomputed and agreed,
`1` on load or verification failure, and `2` on usage errors (wrap the call
in `System.halt/1` as shown — a bare `mix run -e` drops the returned status).
The stdout
report is canonical JSON carrying the corpus digest, registry digest, and raw
index identity. From a repository checkout the same gate is
`mix conformance.verify`; the alias's script is repository-only (the package
does not ship `scripts/`), so from an unpacked package directory use the
escript directly (`mix deps.get` first — the packaged deps are
development-only and the lock does not ship):

```console
$ mix escript.build && ./charter_agreement_protocol --corpus priv/conformance
```

See [Conformance](conformance.md).

## Sign your first evidence (repository demo)

CAP never holds keys. You build a signing input, sign its exact RFC 7515 bytes
with your own Ed25519 key outside CAP, and hand the raw signature (64 bytes
for Ed25519 — the registry row's exact length in general) back
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

## A reviewed companion signer

The hand-rolled `sign` helper above is the whole contract — and if you would
rather not own that glue, [`charter_agreement_signer`](https://hex.pm/packages/charter_agreement_signer) is the
reviewed companion: it takes your `{module, ref}` key handle, resolves the
atomic kid/key snapshot, runs CAP's honest-signer refusals before the key is
used, guards against wrong-key signatures before assembly, and post-sign
verifies through CAP before returning the compact. Verifiers never depend on
it; hosts that hand-roll per the spec remain fully conformant.

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
