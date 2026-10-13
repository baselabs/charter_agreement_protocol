# Charter Agreement Protocol

CAP is a format and a verifier for agreements between two independent parties.
Each party signs exact bytes, and anyone holding those bytes can check later, with
no server and no shared account, what was agreed, which revision was in force at a
given moment, and which agreement a signed action was taken under.

CAP verifies evidence. It never decides anything for you. Every verification result
says what was proven and lists, by name, what it does not prove (who may act, whether
terms were met, legal validity, and so on). Your application makes those calls.

## When to use it

Use CAP when two parties need agreement evidence they can exchange as files or
messages and re-check at any time:

- bilateral terms between companies or between their software agents;
- a party's key history, so rotations and retirements stay checkable;
- signed receipts that tie an action to the agreement it was taken under.

Do not use CAP to decide whether an action is allowed, to check live revocation, to
evaluate contract terms, or to settle legal questions. CAP reports evidence for those
decisions. The [security model](docs/guides/security-model.md) lists exactly what is
and is not proven.

## Install

```elixir
def deps do
  [{:charter_agreement_protocol, "~> 0.5.0"}]
end
```

CAP requires Elixir `~> 1.19` (tested on 1.19 and 1.20) on Erlang/OTP 28 or 29, and has no runtime
dependencies beyond OTP's `:crypto`. To verify ML-DSA (post-quantum) signatures, OTP
must be linked against OpenSSL 3.5 or later. `CharterAgreementProtocol.capabilities/0`
tells you what your runtime can verify.

## Verify a charter

The package ships a two-party charter you can verify right away:

```elixir
alias CharterAgreementProtocol, as: CAP

set =
  :charter_agreement_protocol
  |> Application.app_dir("priv/conformance/cases/chain-verify.json")
  |> File.read!()
  |> JSON.decode!()
  |> Map.fetch!("cases")
  |> Enum.find(&(&1["id"] == "chain-dual-acceptance-valid"))
  |> Map.fetch!("input")

{:ok, facts} =
  CAP.verify_chain(set["revisions"], set["acceptances"], set["descriptors"],
                   set["terminations"], CharterAgreementProtocol.Limits.default())

CAP.governing_revision(facts, ~U[2026-09-01 00:00:00Z])
#=> {:ok, "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"}
```

`verify_chain/5` checks every signature, key history and acceptance from the raw
bytes. `governing_revision/2` returns the revision in force at that instant, or
`:contested` when two valid revisions compete, or `:none` when nothing is in force.
It never picks a winner silently.

[Your first verified charter](docs/guides/getting-started.md) walks through this and
what the facts mean.

## Produce artifacts

CAP builds the exact bytes to sign and checks the result. Signing happens outside CAP,
with your keys. The companion package
[`charter_agreement_signer`](https://hex.pm/packages/charter_agreement_signer) does the
signing for you: it takes your key handle, refuses to sign an acceptance or termination
that conflicts with the artifacts you give it, and verifies its own output before
returning it.
[Produce and verify with the signer](docs/guides/produce-and-verify.md) shows the whole
flow.

## The artifacts

| Artifact | Form | What it records |
|---|---|---|
| Party descriptor | signed (`cap+party`) | One party's verification keys and their history (Ed25519, and ML-DSA from protocol revision 3) |
| Charter revision | canonical JSON | The agreed terms: parties, legal text digest, which text governs, when it takes effect, termination reasons |
| Acceptance | signed (`cap+acceptance`) | One party's signed assent to exact revision bytes |
| Termination notice | signed (`cap+termination`) | One party ending the charter at a stated instant, under a listed reason |
| Receipt | signed (`cap+receipt`) | A signed action tied to the exact revision it was taken under |

## The family

| Package | Language | Role |
|---|---|---|
| `charter_agreement_protocol` (this package) | Elixir | Reference verifier and the bytes to sign |
| [`charter_agreement_signer`](https://hex.pm/packages/charter_agreement_signer) | Elixir | Signs artifacts with your key handle |
| [`@charter-agreement-protocol/verifier`](https://www.npmjs.com/package/@charter-agreement-protocol/verifier) | TypeScript | Independent second verifier |
| [`@charter-agreement-protocol/signer`](https://www.npmjs.com/package/@charter-agreement-protocol/signer) | TypeScript | Signer for Node |

The two verifiers share no code. Both must give the same answer, byte for byte, on
every case in the conformance corpus that ships with this package.

## Documentation

- [Overview](docs/guides/overview.md): how the artifacts fit together.
- Tutorials: [your first verified charter](docs/guides/getting-started.md),
  [produce and verify with the signer](docs/guides/produce-and-verify.md), and two
  Livebook notebooks ([charter tour](docs/notebooks/charter-tour.livemd),
  [fork repair](docs/notebooks/fork-repair.livemd)).
- How-to: [integrate CAP into an application](docs/guides/integration.md),
  [recipes](docs/guides/recipes.md), [handle errors](docs/guides/error-codes.md),
  [upgrade](docs/guides/upgrading-verification-identity.md),
  [implement CAP in another language](docs/guides/implementing.md).
- Reference: [cheatsheet](docs/guides/cheatsheet.cheatmd),
  [artifacts](docs/guides/artifacts.md),
  [limits and profiles](docs/guides/limits-and-profiles.md),
  [the conformance corpus](docs/guides/conformance.md),
  [glossary](docs/guides/glossary.md), and the
  [specification](spec/core.md).

## Status

Version 0.5.0. Protocol revisions 1, 2 and 3 verify. See the [changelog](CHANGELOG.md)
for what changed, and [upgrading](docs/guides/upgrading-verification-identity.md) before
moving between versions.

## Contributing and security

[CONTRIBUTING.md](CONTRIBUTING.md) covers setup and the checks every change must pass.
Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](https://github.com/baselabs/charter_agreement_protocol/blob/main/LICENSE).
