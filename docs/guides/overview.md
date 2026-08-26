# Overview

Charter Agreement Protocol (CAP) is a portable, non-authorizing format and
verification protocol for bilateral commercial agreements between two parties —
acquirers and issuers, platforms and suppliers, agents and their principals —
where each side needs cryptographic evidence of what was agreed, by whom, and
which revision governed a given action, without a central authority deciding for
them.

CAP verifies. It never authorizes. Every API, guide, and notebook in this
package repeats that boundary because it is the product: CAP produces signed,
byte-exact, portable *evidence* that two hosts can independently re-verify and
compare — the decision to act stays with each host.

## The problem CAP solves

A bilateral agreement between two independent parties has recurring failure
points that a shared database cannot answer, because there is no shared
database:

- **Which text governs right now?** Agreements are amended, superseded, and
  terminated. Both parties need the same answer at the same instant, computed
  from evidence either side can re-verify.
- **Did both sides actually assent to *this* revision?** Acceptance must bind
  the exact bytes of the exact revision, signed by a key the counterparty can
  tie to the signing party's declared key history.
- **What happens when a party equivocates?** If one party signs two different
  revisions at the same number, CAP retains both as signed equivocation
  evidence instead of silently picking a winner.
- **Which agreement governed this action?** Receipts bind a signed action to
  the exact charter revision, deployment identity, and grant evidence that
  governed it, so an auditor can recompute the answer years later.

CAP answers each question with structural facts derived from re-verified
signatures and digests. It answers none of them with policy: hosts decide
whether evidence is sufficient.

## The artifact family

| Artifact | Form | Proves |
|---|---|---|
| Party Descriptor | signed compact JWS (`cap+party`) | A party's declared Ed25519 key history, with predecessor-bound key transitions and fork evidence |
| Charter Revision | canonical JSON (unsigned) | The agreed terms: parties, roles, legal-text digest, precedence, effective window, termination reasons, deployment bindings |
| Acceptance | signed compact JWS (`cap+acceptance`) | One party's signed assent to one exact revision, tied to its descriptor key history |
| Termination Notice | signed compact JWS (`cap+termination`) | A pinned party's signed notice that a listed reason takes effect at a pure UTC instant |
| Receipt | signed compact JWS (`cap+receipt`) | That a signed action was decided under an exact revision, deployment digest, and grant reference |

Set-level verification composes the full picture: `verify_chain/5` re-verifies
every artifact from raw bytes and returns structural `ChainFacts`;
`governing_revision/2` answers "which revision governed at this UTC instant"
with a digest, `:contested`, or `:none`. See
[Artifacts](artifacts.md) and [Verification semantics](verification.md).

## Design principles

- **Byte-exactness.** Strict unpadded base64url, deterministic JSON decoding,
  RFC 8785 canonicalization, and domain-separated SHA-256 digests. Two
  implementations — pure Elixir and a builtins-only TypeScript verifier —
  recompute the complete projected fact document of every certified corpus case
  and must produce byte-identical canonical reports.
- **No tie-breaking, ever.** Forked histories are reported as fork evidence and
  contested views. Digest ordering never selects a winner; only an explicitly
  countersigned supersession repair resolves a contested view.
- **Purity.** The production runtime uses only OTP `:crypto`. No filesystem,
  clock, network, environment, process dictionary, or application callbacks in
  verification paths. Callers supply time, limits, trust anchors, and keys.
- **Value-free errors.** Every failure is a closed typed-error vocabulary with
  protocol-owned subjects — rejected input values never appear in errors, so
  verification failures are safe to log.
- **Non-authorizing by construction.** Every facts record carries a closed
  twelve-item `not_verified` floor — tenancy, live policy, authority, effect
  ownership, execution, billing, evaluation truth, legal validity, term
  satisfaction, view completeness, counterparty view, wall clock — that no API
  can shrink. See [Security model](security-model.md).
- **Zero runtime dependencies.** The package runs on OTP crypto alone. ABP and
  BAP enter only as exact, runtime-disabled development/test pins behind the
  frozen cross-protocol conformance vectors. See [Receipts](receipts.md).

## Where CAP sits relative to its siblings

CAP binds to two sibling protocols at exact published identities and keeps its
wire identities disjoint from both:

- **ABP (Agent Blueprint Protocol)** — a Charter Revision names the exact
  blueprint content and deployment digests each party role runs. CAP proves the
  binding is byte-exact; ABP owns what a deployment is.
- **BAP (Bounded Authority Protocol)** — a Receipt's grant reference can carry
  a BAP grant digest, composed exactly from the grant compact's `ath` value.
  CAP proves the digest bytes; BAP owns grant semantics.

Each protocol owns its surface; CAP composes their identities without consuming
their code at runtime.

## What CAP is not

- Not an identity provider: descriptor verification proves signed key
  continuity, not organizational identity or legal existence.
- Not a revocation oracle: no live key-revocation or transparency-log check.
- Not a policy engine: term satisfaction (for example, an indexed price
  meeting a spread) stays in the facts omission floor; hosts compute terms
  independently.
- Not an effect executor: a receipt with `outcome: "effect_committed"` is
  signed evidence from the issuing party, not proof an effect occurred.
- Not a lawyer: legal validity is explicitly outside every verified fact.

## Status

The approved protocol core, certified 85-case corpus, independent second
verifier, 22-mutation battery, and release-candidate gates are implemented and
green in CI. The package is published on Hex as 0.1.0 - the registry
checksum equals the release gate's archive SHA; see the README status
section and [Conformance](conformance.md) for the certified identities.
