# Upgrading verification identity

CAP never authorizes.

This is the consumer transition contract for the release-identity act
(0.4.0; `docs/adr/release-identity.md`). It is issued to the consumer that
asked for it in writing and applies to any consumer that persists the
identity of the release it verified under. It says four things plainly.

## 1. No protocol-side act preserves your historical exact-equality replay

If your persisted identity tuple includes the package version, the package
checksum, or the certified census digest, then ANY upgrade — including
this one — conflicts every historical binding you hold. That is a property
of your tuple, not of this release: no manifest member, semantics version,
or compatibility matrix changes what `"0.2.1"` equals when compared to
`"0.4.0"`. CAP does not ask you to relax equality, to relabel stored
evidence as newly verified, or to skip re-verification; those are your
stated invariants and they are correct.

## 2. What to persist instead: the verification-identity tuple

From 0.4.0, persist and compare this tuple on replay:

- `verification_semantics_version` (from the release manifest, or
  `CharterAgreementProtocol.ReleaseIdentity.verification_semantics/0`),
- the `limits` you actually used — pin them explicitly and record them
  (the manifest publishes the default and maximum values as data),
- `signature_registry_digest` (the signature algorithm registry's
  identity),
- `spec_digest`, unchanged,
- the per-artifact `protocol_revision` (now exposed on every facts record,
  alongside the envelope `alg`), so a revision-2 acceptance is never
  conflated with a revision-3 one.

CAP warrants THESE stable across an upgrade when the compatibility matrix
says so, and never silently moves them. Release-distribution identities —
`package_version`, `package_checksum`, `corpus_digest` — are NOT warranted
stable-under-upgrade: the census regenerates when the certified corpus
grows, and the package version moves by definition. Bind to them for
supply-chain reasons; do not make them your replay identity.

## 3. The retroactive mapping, today

Pre-0.4.0 releases carry none of these members. The mapping is published
as data (`ReleaseIdentity.verification_semantics_history/0`, mirrored in
the manifest's `compatibility` member) and certified per release by the
historical differential gate: semantics 1 = 0.1.0; 2 = 0.2.0–0.2.1
(revision-2 admissions); 3 = 0.3.0–0.3.2 (ML-DSA admissions, seven
timestamp floors, the default byte budget); 4 = 0.4.0 (the descriptor
timestamp floor). Each enumerated transition carries its direction and
description; the claim's scope is finite evidence over named inputs —
under this release's default limits, on a capable substrate, every case
in every frozen certified corpus reproduces its recorded verdict except
the enumerated transitions.

## 4. The dependency footgun

`~> 0.2.1` admits neither 0.3.x nor 0.4.0 — the requirement itself must
move. `~> 0.4.0` admits a later `0.4.x` while an exact runtime identity
check stays exact: a lock resolution to `0.4.1` would then fail closed as
an identity mismatch until YOUR pinned constants move. Whether you pin
`== 0.4.0` or track `~> 0.4.0` with migration steps is your call; the
mechanics are stated here so it is a call, not a surprise.

## Substrate-limited deployments (the honest subset)

A deployment whose runtime cannot verify ML-DSA (for example Ubuntu 24.04
with OpenSSL 3.0.x) probes `capabilities()` at boot, verifies its
Ed25519 corpus green, and receives
`:algorithm_unsupported_on_substrate` — a named, testable, honest
diagnostic — for revision-3 ML-DSA artifacts, never a forgery verdict.
`Capability.new(algorithms: [...], revisions: {min, max})` narrows
admission to a declared subset, enforced before any cryptographic work;
widening it when the substrate upgrades is a profile change, not a
re-audit. See the capability-limited CI lane for the executed evidence on
a real ML-DSA-less substrate.

## The consumer acceptance lane

The request to publish a consumer's rehearsal evidence (a real populated
pre-upgrade database exercising old-accepted replay, new import,
changed-body conflict, cross-tenant access, and restart recovery) is
ACCEPTED: it is a consumer acceptance lane, named as such, linked from
the conformance guide, held outside the certified corpus and outside the
certified-identity surface. It is the consumer's own evidence, linked and
described by CAP; it earns no conformance credit, and CAP's release never
gates on a consumer's database.
