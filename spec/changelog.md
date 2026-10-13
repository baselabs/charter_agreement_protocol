# Specification changelog

Independent record of revisions to the specification set (`core.md`,
`security-considerations.md`, `privacy-considerations.md`,
`registry-policy.md`, `evolution.md`, `schemas/`, and the generated
`requirements.md`). This record is independent of the package
changelog (`../CHANGELOG.md`): a package release ships a specification
revision, but a specification revision does not require a package
release.

## 2026-10-13: pre-sign API

Add the CAP-SIGNING requirements for ordered preparation, caller limits,
key shape and membership, shared context preparation, runtime support,
finishing and malformed retained context handling. Add `signing.prepare`
to the certified corpus. Existing verification semantics remain 5.

## 2026-10-13: profile admission covers re-verified context

- `core.md` section 4: a call that re-verifies caller-supplied context
  applies the caller's profile to every artifact in it, the supplied
  revision first, then the descriptor history or artifact set, then the
  artifact itself; a revision-only receipt context still admits the
  receipt's envelope against the profile,
  [CAP-PROFILE-context-admission].
- The reference before 0.5.0 applied the profile only to the artifact under
  verification in standalone acceptance, termination and receipt calls, so
  a narrowed profile could pass a call whose context it excluded. Only
  calls given a narrowed profile change; under the full profile every
  verdict is unchanged [CAP-PROFILE-narrow-verification].
- The `party_descriptor.verify`, `acceptance.verify`, `termination.verify`
  and `receipt.verify` surfaces take an optional `profile` input,
  `party_descriptor.verify` takes a `predecessor_compacts` history, and
  `receipt.verify` takes a `revision_text` context in place of `chain`; twenty-four cases evidence the rule.
- `requirements.md`: regenerated with the new requirement.

## 2026-10-13: termination closure and artifact-set ceilings stated

- `core.md` section 5: the artifact-set ceilings become a normative
  statement, [CAP-CHAIN-artifact-set-bounds]: each artifact list holds at
  most `max_artifact_set_items` items and all artifacts together at most
  `max_artifact_set_bytes` bytes, checked before any decode or signature
  check.
- `core.md` section 6: a verified termination naming the revision governing
  at its `effective_at` closes the charter from that instant,
  [CAP-CHAIN-termination-closes].
- Both describe behavior the reference already had (`Limits` since 0.3.0,
  termination closure since 0.1.0); a second implementation that lacked
  them passed every previously certified case. No verdict changes.
- `requirements.md`: regenerated with the two new requirements and the
  corpus cells that now evidence the closed claim sets, revision decode
  strictness, and the new cases.

## 2026-10-13: algorithm-prose correction in the considerations

- `security-considerations.md` and `privacy-considerations.md`: the
  forged-signature and public-key passages named Ed25519 as the only
  algorithm; they now name the registered algorithms (Ed25519, or
  ML-DSA-44, ML-DSA-65 and ML-DSA-87 from `protocol_revision` 3) and point
  to core section 4.1. No requirement identifier, schema byte, or verdict
  changes; the specification digest re-records.

## 2026-09-15 — signature-prose generalization correction

- `core.md`: the party-descriptor and receipt signature MUST-clauses state
  the registry row's key algorithm instead of naming Ed25519 — completing
  the revision-3 act's recorded consequence ("`spec/core.md`'s
  Ed25519-specific signature prose generalizes to the registry",
  `docs/adr/ml-dsa-admission.md`), which the 0.3.0 release left unfinished
  in these two clauses. No requirement identifier, schema byte, or verdict
  changes; the specification digest re-records.

## 2026-08-26 — corpus coverage closure revision

- `core.md`: five new normative statements (equivocation pairing, chain
  input non-emptiness, the extension envelope closure ladder, descriptor
  decode shape, compact envelope well-formedness) bound to the five new
  matrix requirements.
- `requirements.md`: regenerated — 45 requirements over 61 applicability
  cells and 85 certified cases.

## 2026-08-26 — initial specification set

- `core.md`: initial normative core. RFC 2119/8174 conformance language
  with BCP 14 boilerplate; every normative statement carries a stable
  requirement identifier bound to evidence in the generated
  requirements matrix (40 requirements, bidirectionally complete).
- `schemas/`: the single normative machine grammar — eleven JSON Schema
  2020-12 bounded-subset documents covering the five artifact claim
  sets, the extension envelope, the compact-JWS protected header, the
  tagged-digest and timestamp grammar, and the corpus index and report
  formats, with per-constraint enforced negatives.
- `security-considerations.md`, `privacy-considerations.md`: initial
  threat model and data-exposure analysis.
- `registry-policy.md`: extension namespace and receipt-profile
  registration policy, fail-closed for unknown critical namespaces.
- `evolution.md`: algorithm agility, ML-DSA (RFC 9964) as the named
  migration target, the post-quantum hybrid note, `protocol_revision`
  as the sole version vehicle, and the revisited spec-technology bets.
- `docs/protocol.md` demoted from normative text to the implementation
  guide, cross-linked to this set.

## Revision 3 record — 2026-09-14

`protocol_revision` 3 (the ML-DSA registry act, ADR `ml-dsa-admission.md`):

- `core.md` §4/§4.1: the registry gains the RFC 9964 names `ML-DSA-44/65/87`
  at revision 3 with exact per-name key and signature byte lengths as
  registry data; the mint set is (Ed25519, 2) and (ML-DSA-65, 3). New
  requirements `CAP-ALG-mldsa-registry-rows`,
  `CAP-PARTY-DESCRIPTOR-key-grammar-gate`, and `CAP-SIGNATURE-mldsa-lengths`.
- `core.md` §4.2: the key grammar is gated on descriptor revision — an
  ML-DSA key in a revision-1/2 descriptor rejects.
- `core.md` §10 and `evolution.md`: RFC 9964 reference added; the migration
  target section becomes the record of the admitted act.
- `security-considerations.md`: unchanged threat model; ML-DSA rows enforce
  exact lengths, no torsion surface exists in lattice schemes.
- `schemas/`: the protected-header `alg` enum, the key `algorithm` enum, the
  key-encoding length window, and the per-artifact `protocol_revision`
  maximums widen to revision 3.
- `requirements.md` regenerated (50 bound requirements).
