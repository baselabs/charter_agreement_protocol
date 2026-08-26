# Algorithm-name agility: the revision-2 alg bundle

Date: 2026-08-26

## Status

Accepted. Governs `protocol_revision` 2. Implemented 2026-08-26 (same day,
after the standards-readiness tickets landed): the registry module, the
framing-layer binding rule in both implementations, the schema/spec
surfaces, and the recertified both-population corpus. One deviation from
the scouted design, discovered by the mutation gate: the producer's
explicit emission-revision gate was REMOVED as redundant — the binding
rule at the provisional decode already makes the producer unable to
construct a non-conforming artifact (its named mutation survived, which
the gate discipline treats as dead logic); the mint contract holds by
construction, not by a redundant check.

## Context

RFC 9864 ("Fully-Specified Algorithms for JOSE and COSE", Proposed
Standard, October 2025) registers the fully-specified JOSE alg names
`Ed25519` and `Ed448` and marks the polymorphic `EdDSA` registration
**Deprecated** — deprecated, not prohibited; existing use remains valid,
but new registrations must be fully-specified and the registry's direction
is explicit. CAP revision 1 closed the protected header's `alg` to exactly
`EdDSA` (spec/core.md §protected header; `spec/schemas/compact-jws-protected-header.json`),
while the descriptor key grammar already names keys by the fully-specified
`algorithm: "Ed25519"` — the naming split is purely JOSE-registration
history, and RFC 9864's `Ed25519` denotes exactly the operation CAP
already performs (same curve, same signature; keys are closed to 32-byte
Ed25519 with no Ed448 path, so no second cryptographic operation exists).

A new protocol entering standardization while minting a registry-deprecated
identifier is a standing review flag; the forcing event that would make
the change urgent (`EdDSA` moving Deprecated→Prohibited, or verifier
ecosystems refusing it) would arrive post-adoption as verdict flips on
live artifact chains. CAP's adoption is portfolio-only today — the
cheapest window is now.

## Decision

Revision 2 carries exactly one semantic change — the alg-name contract:

1. **The binding rule (per-artifact, not per-view).** Decoders accept
   `alg: "EdDSA"` at any accepted `protocol_revision`; `alg: "Ed25519"`
   requires `protocol_revision >= 2`; the accepted revision set is {1, 2}
   and unknown revisions fail closed. An artifact carrying `Ed25519` at
   revision 1 is REJECTED — no honest producer could have minted it
   (revision 1's spec pinned `EdDSA`), and keeping it red is what gives
   the corpus's per-name negatives their content.
2. **Emission.** The signing-input producer emits exactly
   (`"Ed25519"`, `protocol_revision` 2). Old artifacts verify forever;
   nothing new mints a deprecated-named artifact.
3. **Cross-revision composition.** Artifacts mix freely within a view —
   a revision-2 acceptance may anchor a revision-1 charter revision.
   Charters outlive revisions; the TypeScript verifier's
   acceptance-revision equality (verifier/core.ts, `acceptanceFromCompact`)
   is replaced by the accepted-set semantics, and the TypeScript verifier
   gains the revision-range check it never had.
4. **The closed set is the registry.** Each implementation keeps one
   single-source closed set with the row shape
   `{name, min_protocol_revision, key_algorithm}`; for revisions 1–2 the
   `key_algorithm` column is `Ed25519` for both rows. This set IS the
   algorithm registry `spec/evolution.md` describes as "data-driven": a
   future algorithm (the named migration target is ML-DSA, RFC 9964) is
   added by the same registry-and-revision act — a new row plus the key
   grammar its column requires — never by forking the code path.
5. **Decoded structs tell the truth.** Every codec's extraction carries
   the artifact's actual `protocol_revision` (the revision-1-era code
   hard-pinned the literal 1).

## Consequences

- Verdict audit: nothing green→red. Red→green: (rev 2, Ed25519) — the
  intended class; (rev 2, EdDSA) — the compatibility case (a downstream
  producer that bumps revision before renaming emission must not brick);
  mixed-revision views. (rev 1, Ed25519) stays red.
- Certified corpus: regenerated with both populations — (rev 1, `EdDSA`)
  legacy fixtures, (rev 2, `Ed25519`) primary, (rev 2, `EdDSA`)
  compatibility, and the mixed-revision acceptance view — plus negatives:
  (rev 1, `Ed25519`), unknown/case-mutated names, and revision 3 as the
  cross-implementation fail-closed case. **Legacy fixtures pin revision 1
  and `EdDSA` literally, on purpose**: they are an independent minter in
  the sense `docs/test-vectors.md` asks of third implementations;
  "modernizing" them to read the shared constant would collapse the
  legacy population into derivations of current code and destroy its
  evidentiary value.
- Recertification: `corpus_digest`, `index_sha256_base64url`, and
  `spec_digest` re-pin (`spec/` gains the binding rule, the widened
  MUST-clause, the schema enum, and the RFC 9864 reference); the extension
  `registry_digest` is unaffected; `docs/test-vectors.md`'s live identity
  values re-record.
- Downstream: `charter_agreement_signer` pins CAP `~> 0.1.0` with a
  deliberate-bump wall (its ADR-0002) — adopting revision 2 is a reviewed
  signer release, by design.

## Rejected alternatives

- **A full dispatch-table registry now** — two rows identical except the
  name is machinery with nothing to dispatch; the next algorithm (ML-DSA)
  changes key grammar and bounds and was never a one-row append. The row
  shape is adopted; the table machinery is not.
- **Pure set-widening without the binding rule** — makes both names legal
  at both revisions, reducing per-name negatives to spelling mutations and
  green-lighting a class no honest revision-1 producer could mint.
- **Leaving the TypeScript acceptance-revision equality in place** —
  silently re-litigates the settled mixability decision; the first real
  post-cutover acceptance of a pre-existing charter would verify in
  Elixir and false-negative in TypeScript, discovered by a counterparty
  rather than by a gate.

## Revisit triggers

- `EdDSA` moving Deprecated→Prohibited in the JOSE registry: a future
  revision drops the `EdDSA` row; whether pre-existing artifacts remain
  verifiable is that revision's policy question (recorded, not decided).
- ML-DSA adoption (RFC 9964) per `spec/evolution.md`'s named migration
  target: occupies the reserved `key_algorithm` slot via the same
  registry-and-revision act.
- A third alg-name class appearing in the JOSE registry: same act.
