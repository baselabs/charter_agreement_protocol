# Release identity: the manifest contract, the semantics identity, and the capability profile

Date: 2026-09-24

## Status

Accepted. Governs the 0.4.0 release-identity act. Backed by the judged
design of 2026-09-23 (two adversarial review lenses plus an independent
judge; the scout records live under the repository's process archive), by
substrate probes (the noble-substrate observation below), and by owner
rulings recorded the same day: both no-versioning boundary exceptions
approved, the BA rehearsal lane accepted, the BA transition contract
authorized for issue, CAS alignment handed off, the descriptor timestamp
floor fixed, Hex publication held.

## Context

The one live consumer (bounded_authority) verifies with the installed
package, persists the release identity it verified under, and requires
exact equality on replay — any upgrade conflicts every historical binding
because the persisted tuple includes package version and census digests.
Meanwhile 0.3.0 had changed verdicts for existing valid inputs (seven
timestamp members gained a 1..64 byte floor; the default byte budget
reded oversized views), and substrates that cannot verify ML-DSA
(Ubuntu 24.04, OpenSSL 3.0.x) fail-closed those artifacts as
`signature_invalid` — indistinguishable from forgery. The consumer asked,
in writing, for a versioned machine-readable identity contract, an honest
capability story, revision exposure in verification output, and stated
immutability.

One premise the whole capability workstream rests on was closed by direct
observation before implementation: on ubuntu-noble (OpenSSL 3.0.13), OTP
28.5 and 29.1 both report `:crypto.supports(:public_keys)` WITHOUT any
`:mldsa*` atom — the declaration carries both the OTP and the linked-
OpenSSL axes, and the substrate diagnostic is reachable on exactly the
substrate that asked for it.

## Decision

### The manifest contract

`priv/release-metadata.json` is a versioned public contract:
`manifest_version` versions the SHAPE (additive-only; consumers MUST
ignore unknown members; removal, renaming, or retyping bumps it in a
breaking release). Every member that is data-in-code is the recorded
projection of a pure function — `Limits.default/0` and `Limits.maximums/0`,
`Algorithm.registry/0` and `Algorithm.registry_digest/0` (the signature
registry's own identity; the extension registry's digest never identified
signature algorithms), `ReleaseIdentity.manifest_version/0`,
`verification_semantics/0`, and `compatibility/0` — and the
release-candidate gate asserts the manifest bytes equal the live values
member by member. The archive content pin authenticates the bytes; the
gate comparison authenticates their truth.

### The verification-semantics identity

`verification_semantics_version` identifies the verdict function of the
verification core over artifact-set inputs, quantified over all valid
`Limits`, on a capable substrate, with no profile narrowing. It moves to a
new value against the immediately prior release when: some input's verdict
class changes in EITHER direction (admissions count — a consumer whose
evidence records "did not verify" is materially affected when that becomes
green); the error code for some input changes; any `Limits.default/0`
value changes (defaults are the instantiation every non-choosing consumer
inherits); or some input that returned a verdict now raises. Error
subjects and details, substrate capability outcomes (an
implementation-local diagnostic), crash-to-typed conversions, and
facts-record fields are outside the identity. This is deliberately the
strict definition — the per-release cost is that a registry act bumps the
value; the payoff is that documentation-only releases hold it constant
while the certified census digest moves, which is the entire point of
separating the two.

The retroactive mapping, published as data
(`ReleaseIdentity.verification_semantics_history/0`) and certified by the
standing differential gate:

| Semantics | Packages | Transitions since prior |
|---|---|---|
| 1 | 0.1.0 | — |
| 2 | 0.2.0, 0.2.1 | revision-2 admissions (red→green) |
| 3 | 0.3.0–0.3.2 | ML-DSA admissions; seven timestamp floors (green→red); default byte budget (green→red at defaults); improper lists (crash→typed) |
| 4 | 0.4.0 | the descriptor timestamp floor (green→red) — the last live timestamp asymmetry |

### The certification instrument and its exact claim

A standing per-release gate runs every frozen certified corpus (v0.1.0
through v0.3.2) under the current package through the pure runner, with
verdict agreement required except an enumerated per-(tag, case)
transition allowlist and a per-family census tie to each frozen index's
own corpus digest. The allowlist comparison is red-provable by
mutation (observed: a direction flip fails the gate); the gate runs in
every quality battery. The published
claim is worded to the instrument: finite evidence over named inputs,
never a proof of universal equivalence. The corpus loader gains an
explicit historical mode that keeps every released-artifact integrity
check (self-digest, per-file hashes, file set, count reconciliation) and
relaxes only the compiled applicability floor — a current-certification
instrument that a frozen index predating this package's surfaces cannot
satisfy.

### Capability honesty

`capabilities()` derives one verifiable verdict per registry row from
pinned known-answer verification vectors gated on the runtime's declared
public-key algorithms — the operation itself, not the runtime's claim
about itself — with linked-crypto identity informational only. The
TypeScript mirror answers with the same instrument and the same pinned
bytes. `:algorithm_unsupported_on_substrate` is an implementation-local
DIAGNOSTIC, not a protocol verdict: it is outside the conformance verdict
surface and outside cross-verifier report identity, fires only after
every deterministic check has passed and the substrate is the sole
obstacle (a forged artifact never earns a retryable diagnosis), and
propagates through every aggregator including the receipt path's
exact-one-verifier partition. Its real-substrate evidence is the
capability-limited CI lane (Ubuntu 24.04 / OpenSSL 3.0.13), always green,
asserting honest failure where the capable lanes assert green
verification.

### The capability profile

`Capability.Profile` is caller-supplied pure data, validated like
`Limits`, failing closed with `:invalid_profile` before verification
begins. Two axes — the accepted envelope `alg` names and the accepted
`protocol_revision` range — applied per artifact, threaded through every
verify seam (never a pre-pass: a pre-pass would change error precedence),
admitting out-of-profile artifacts with `:algorithm_outside_profile` or
`:revision_outside_profile` before any cryptographic work, on every
substrate alike. The profile deliberately does NOT constrain declared key
material: a descriptor declaring ML-DSA keys that is Ed25519-signed is in
profile for an Ed25519-only deployment, and a deployment that must
exclude ML-DSA-keyed lineages narrows the revision axis (ML-DSA key
material is legal from revision 3). The full profile is exactly
verification without one.

### Immutability

Released identities — digests, corpora, manifests — are never mutated in
place. Corrections are new releases. The retroactive mapping above is a
documented classification of already-released artifacts, never a rewrite
of a released manifest; pre-0.4.0 packages carry none of these members
and never will.

## Consequences

- Consumers bind to the semantics identity, the limits they use, the
  signature-registry digest, and the per-artifact `protocol_revision`
  (exposed on every facts record; the signed artifacts' records also carry
  the envelope `alg` — unsigned revision facts carry none, there is no
  envelope, the field is nil by design),
  instead of census digests and package numbers; the transition contract
  for the existing consumer is issued with this release and states
  plainly that no protocol-side act can preserve its historical
  exact-equality replay — the identity tuple it persists must be
  re-scoped, not relabeled.
- The per-release cost: every release re-runs the differential gate and
  re-records the census; every registry act bumps the semantics value.
- The declared floors are unchanged: OTP {28, 29} with a linked OpenSSL
  >= 3.5 for the CERTIFIED corpus; the capability-limited lane is
  evidence, not a floor change — a substrate without ML-DSA is a
  supported honest-failure deployment through the profile and the
  diagnostic.

## Rejected alternatives

- Binding the semantics identity to caller-pinned limits with admissions
  excluded (the consumer uses default limits and records non-verifications;
  an identity that can hold constant while flipping the requesting
  consumer's evidence red is a reassurance, not an identity).
- A prose compatibility matrix (the drift surface the 0.3.1 release had to
  repair; the gate over the VALUE is what makes the member admissible at
  all under the no-versioning rule).
- Deriving the capability verdict from `:crypto.supports` alone (the
  operation, executed, is the honest instrument; the declaration is the
  gate that keeps the probe safe on substrates that lack the operation).
- A profile axis over declared key material (two codes for one condition —
  the key grammar's own revision gate already speaks).

## Revisit triggers

- A composite-signature RFC or a JOSE registry change lands in the same
  agility slot: the registry act bumps the semantics identity and the
  matrix records the transitions.
- A second consumer asks for a different identity axis: extend the
  manifest additively; the schema version does not move.
