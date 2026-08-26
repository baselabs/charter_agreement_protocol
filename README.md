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
| Party Descriptor | signed JWS (`cap+party`) | A party's Ed25519 key history with predecessor-bound transitions and fork evidence |
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
domain-separated SHA-256 digests. A certified 84-case corpus runs through a
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

Elixir ~> 1.20; zero runtime dependencies (OTP `:crypto` only). Until the
package is published, depend on the exact commit your CI verified:

```elixir
{:charter_agreement_protocol,
 git: "https://github.com/baselabs/charter_agreement_protocol.git",
 ref: "f2a6165a4ac58ceb6fca3fd1d0c451b2409ffea6"}
```

Then verify the shipped, certified corpus from your dependent project:

```console
$ mix run -e 'CharterAgreementProtocol.Conformance.Cli.run(["--corpus", "deps/charter_agreement_protocol/priv/conformance"])'
```

The command prints the canonical JSON report; a returned status of `0` means
all 84 certified cases recomputed and agreed. Full walkthrough:
[Getting started](docs/guides/getting-started.md).

## Try it

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
  raw 64-byte signature, and hosts post-verify before serving the compact.

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
0.1.0 package is frozen pending publication: the archive at this commit is
the reviewed candidate, and building it is still not authorization to
publish — tagging, pushing, and `mix hex.publish` require explicit
operator authorization.

## Development

```
mix deps.get
mix quality
```

`mix quality` is the complete gate — audits, formatting, warnings-as-errors
compile, strict credo, the full test suite with its coverage threshold,
certified-conformance verification and regeneration identity, all 22 named
source mutations, Elixir/TypeScript verifier agreement over repository and
unpacked-package corpora, dialyzer, docs, and the reproducible
release-candidate archive. Contribution bar and invariants:
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

Apache-2.0 — see [LICENSE](LICENSE).
