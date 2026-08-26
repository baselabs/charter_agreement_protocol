# Specification changelog

Independent record of revisions to the specification set (`core.md`,
`security-considerations.md`, `privacy-considerations.md`,
`registry-policy.md`, `evolution.md`, `schemas/`, and the generated
`requirements.md`). This record is independent of the package
changelog (`../CHANGELOG.md`): a package release ships a specification
revision, but a specification revision does not require a package
release.

## 2026-08-26 — corpus coverage closure revision

- `core.md`: five new normative statements (equivocation pairing, chain
  input non-emptiness, the extension envelope closure ladder, descriptor
  decode shape, compact envelope well-formedness) bound to the five new
  matrix requirements.
- `requirements.md`: regenerated — 45 requirements over 61 applicability
  cells and 84 certified cases.

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
