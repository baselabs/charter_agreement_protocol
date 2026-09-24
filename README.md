# Charter Agreement Protocol

Portable, non-authorizing charter-agreement format and verification protocol
for bilateral commercial agreements. CAP verifies signed, byte-exact evidence
of what two parties agreed, which revision governed a given instant, and which
agreement state governed a signed action — without a central authority, and
without ever making the decision for you.

**CAP verifies. It never authorizes.** Every facts record carries a closed
twelve-item `not_verified` floor — authority, execution, billing, term
satisfaction, legal validity, and more — that no API can shrink. Hosts read
the evidence and decide.

## What it does

| Artifact | Form | Proves |
|---|---|---|
| Party Descriptor | signed JWS (`cap+party`) | A party's declared key history (Ed25519, and ML-DSA from `protocol_revision` 3) with predecessor-bound transitions and fork evidence |
| Charter Revision | canonical JSON | Agreed terms: parties, roles, legal-text digest, precedence, effective window, termination reasons, exact deployment bindings |
| Acceptance | signed JWS (`cap+acceptance`) | Bilateral signed assent to exact revision bytes |
| Termination Notice | signed JWS (`cap+termination`) | Signed closure of the charter at a pure UTC instant |
| Receipt | signed JWS (`cap+receipt`) | A signed action bound to exact revision coordinates, deployment digest, and grant evidence |

Set-level verification composes the artifacts into structural facts:
`verify_chain/5` re-verifies everything from raw bytes;
`governing_revision/2` answers "which revision governed at this instant" with
a digest, `:contested`, or `:none` — never a silent tie-break. Same-signer
equivocation is retained as signed evidence with no winner. The only repair
for a contested view is a countersigned supersession revision.

The foundation is byte-exact by construction: strict unpadded base64url,
deterministic tagged JSON decoding, RFC 8785 canonicalization, and
domain-separated SHA-256 digests. A certified 100-case corpus runs through a
pure Elixir runner and a builtins-only Node TypeScript verifier that must
produce byte-identical canonical reports — two independent implementations,
zero shared code.

## When to use it — and when not

Use CAP when two independent parties need portable, re-verifiable agreement
evidence exchanged as bytes: agent commerce charters, bilateral supplier
terms, key-history continuity proofs, action receipts for audit.

Do not use CAP for authorization decisions, live revocation checks, term
evaluation (CAP leaves `term_satisfaction` in its omission floor), legal
adjudication, or single-party self-attestation — every one of those is
explicitly outside what verification proves. See the
[security model](docs/guides/security-model.md) for the full proves/never-proves
table.

## Quick start

Elixir ~> 1.19 (tested lines 1.19.x and 1.20.x) on Erlang/OTP 28 or 29 —
the range and the supported-OTP set are enforced in-repo (Mix refuses an
Elixir outside the range and `config/config.exs` refuses an OTP major outside
the set, both before anything compiles), and they move in lockstep with
`.tool-versions` and the CI lanes (see
[the supported-toolchain ADR](docs/adr/supported-otp-set.md)). Zero runtime
dependencies (OTP `:crypto` only). From
`protocol_revision` 3 the runtime floor has a second axis: ML-DSA verification
needs an OTP runtime whose linked crypto library is OpenSSL ≥ 3.5 (FIPS 204
landed there; OTP ≥ 28.1 with OpenSSL ≥ 3.5 is the declared floor — a runtime
linked against OpenSSL 3.0.x cannot generate or verify ML-DSA keys, and OTP 27
exposes no ML-DSA algorithms to `:crypto` even with OpenSSL ≥ 3.5 linked). The
shipped corpus contains ML-DSA cases, so the quick-start verification below
needs that floor too:

```elixir
{:charter_agreement_protocol, "~> 0.4.0"}
```

Then verify the shipped, certified corpus from your dependent project:

```console
$ mix run -e 'System.halt(CharterAgreementProtocol.Conformance.Cli.run(["--corpus", "deps/charter_agreement_protocol/priv/conformance"]))'
```

The command prints the canonical JSON report and exits `0` when
all 100 certified cases recomputed and agreed. Full walkthrough:
[Getting started](docs/guides/getting-started.md).

## Try it

- TypeScript verifier on npm:
  `npm install @charter-agreement-protocol/verifier` — the independent
  second verifier as a standalone package under the
  `charter-agreement-protocol` organization, with the certified corpus
  vendored inside.
- Runnable notebooks: [charter tour](docs/notebooks/charter-tour.livemd) and
  [fork repair](docs/notebooks/fork-repair.livemd) — a complete bilateral
  charter with real Ed25519 signatures, and a manufactured equivocation with
  its countersigned repair.
- Repository demo: `mix run examples/supplier_fork_demo.exs` — equivocation
  evidence, contested governing view, an action receipt inside the fork, and
  the repair, in nine lines of output.

## Guarantees at the call boundary

- Failures are typed and **value-free** — closed error codes, protocol-owned
  subjects, never rejected input — so verification failures are safe to log.
- Facts implement **redacted inspection** — retained signed artifacts never
  appear in logs.
- Verification is **pure**: no clock, filesystem, network, or environment.
  Callers supply time, limits, trust anchors, and keys.
- Key custody stays outside the protocol: CAP builds the exact RFC 7515
  signing input, you sign it, `assemble_compact/2` accepts only an external
  raw signature at the registry row's exact length (64 bytes for `Ed25519`;
  2420/3309/4627 for the ML-DSA parameterizations), and hosts post-verify
  before serving the compact.
  A reviewed companion signer implements that host glue for you —
  [`charter_agreement_signer`](https://hex.pm/packages/charter_agreement_signer) (atomic kid/key snapshot,
  wrong-key guard, post-sign verify, refusal surfacing); verifiers never
  depend on it, and hosts may always hand-roll per the spec instead.

## Guides

- [Overview](docs/guides/overview.md) — the problem, the artifact family, the
  design principles
- [Getting started](docs/guides/getting-started.md) — install, first
  verification, first signature
- [Artifacts](docs/guides/artifacts.md) — every artifact's wire shape and
  closed claim set
- [Verification semantics](docs/guides/verification.md) — forks, contested
  views, supersession, governing computation
- [Receipts](docs/guides/receipts.md) — binding actions to agreements; ABP
  and BAP identity composition
- [Extensions and profiles](docs/guides/extensions.md) — the registry,
  criticality, quarantine
- [Security model](docs/guides/security-model.md) — proves / never proves,
  the omission floor, architecture enforcement
- [Recipes](docs/guides/recipes.md) — end-to-end integration patterns
- [Conformance](docs/guides/conformance.md) — the certified corpus, the gate
  battery, the certified identities
- [FAQ](docs/guides/faq.md)
- [Protocol foundation](docs/protocol.md) — the normative specification
- [Indexed-price profile](docs/profiles/indexed-price.md),
  [errata policy](docs/errata.md), ADRs:
  [no version tokens in identifiers](docs/adr/no-versioning-rule.md),
  [conformance and release-candidate boundary](docs/adr/conformance-release-candidate.md)

## Status

The approved protocol core, normative specification set, certified corpus
with four recorded identities, independent second verifier, mutation
battery, and release-candidate gates are implemented and green in CI. The
0.3.x line carries `protocol_revision` 3 — the ML-DSA registry act
(RFC 9964): the `ML-DSA-44/65/87` names verify from revision 3, the
descriptor key grammar admits ML-DSA keys gated on revision, producers
mint `ML-DSA-65` at revision 3 alongside `Ed25519` at revision 2, and the
resource boundary is byte-weighted for PQ-sized artifacts. 0.3.1 corrects
the declared runtime floor (OTP ≥ 28.1 **with a linked OpenSSL ≥ 3.5**),
runs CI on an ML-DSA-capable substrate, and re-trues the shipped
documentation to the revision-3 surface. `protocol_revision` 2
(RFC 9864 alg names) and revision-1 artifacts remain verifiable. Building
an archive remains verification evidence only — never authority to
publish.

## Development

```
mix deps.get
mix quality
```

`mix quality` is the complete gate — audits, formatting, warnings-as-errors
compile, strict credo, the full test suite with its coverage threshold,
certified-conformance verification and regeneration identity, all 25 named
source mutations, Elixir/TypeScript verifier agreement over repository and
unpacked-package corpora, dialyzer, docs, and the reproducible
release-candidate archive. Contribution bar and invariants:
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache-2.0 — see [LICENSE](LICENSE).
