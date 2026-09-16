# Specification changelog

Independent record of revisions to the specification set (`core.md`,
`security-considerations.md`, `privacy-considerations.md`,
`registry-policy.md`, `evolution.md`, `schemas/`, and the generated
`requirements.md`). This record is independent of the package
changelog (`../CHANGELOG.md`): a package release ships a specification
revision, but a specification revision does not require a package
release.

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
