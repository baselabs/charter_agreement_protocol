# Evolution

How this specification changes: algorithm agility first, versioning by
`protocol_revision`, and the explicitly revisited technology bets that
shaped the document set. Nothing here grants authority to deprecate a
published revision silently; the errata policy and this document govern
change.

## Algorithm agility

The signature algorithm is named, not hard-coded into the wire. The
protected header carries `alg` closed to `EdDSA` in revision 1, and
verification resolves keys from the declared descriptor history whose
`algorithm` member names the key's scheme. Adding an algorithm is a
registry-and-revision act: a new `alg` value, a new key `algorithm`
value, new point-encoding rules where the scheme needs them, and a
`protocol_revision` advance — never a parallel artifact family, media
type, or header shape. The verification path's algorithm dispatch is
data-driven so a second algorithm does not fork the code path: the closed
`alg` name set (with each name's minimum revision and key algorithm) is
itself the registry — a name or algorithm lands by the same
registry-and-revision act that added `Ed25519` in revision 2.

## Named migration target: ML-DSA (RFC 9964)

The anticipated second signature algorithm is ML-DSA, the post-quantum
Module-Lattice Digital Signature Standard (NIST FIPS 204, final August
2024). RFC 9964 ("ML-DSA for JOSE and COSE", Proposed Standard, May
2026) registers the JOSE identifiers `ML-DSA-44`, `ML-DSA-65`, and
`ML-DSA-87` (parameterizations of FIPS 204 with public keys of 1312,
1952, and 2592 bytes and signatures of 2420, 3309, and 4627 bytes;
pure ML-DSA only — the pre-hashed HashML-DSA variants are out of scope
of that registration, and the `ctx` parameter is the empty string). A
future protocol revision that adds ML-DSA cites those identifiers and
extends the descriptor key grammar's `algorithm` enumeration and byte
bounds accordingly; the compact-JWS envelope, digest domains, and
canonicalization are unchanged.

**Post-quantum hybrid note.** Hybrid PQ/T composite signatures for
JOSE/COSE are still Internet-Drafts (draft-ietf-jose-pq-composite-sigs).
This specification does not adopt composites; when a composite reaches
RFC, its `alg` values land in the same agility slot as ML-DSA would,
and a revisited revision decides between pure-PQ and hybrid adoption on
the then-current guidance.

## protocol_revision as the migration vehicle

`protocol_revision` is the sole version identity of the wire. Semantic
wire changes — new algorithm, new member, changed grammar — advance the
number; a decoder rejecting an unknown revision fails closed. There are
no parallel module families, path families, or media types for new
revisions (the repository's no-versioning rule), so two implementations
that agree on a revision agree on the whole grammar. Prose-only changes
(clearing, considerations, this document) do not advance the number and
are recorded in `changelog.md`.

## Spec-technology bets and revisit triggers

The document set rests on three explicitly revisited technology bets
(recorded with their bases; each is reversible without wire changes):

- **B1 — authoring pipeline.** The spec is authored in Markdown
  convertible to RFCXML (kramdown-rfc-class tooling) for a future
  Datatracker submission, with RFC 2119/8174 (BCP 14) boilerplate.
  *Revisit when:* the IETF authoring toolchain changes its default
  Markdown dialect.
- **B2 — single grammar.** JSON Schema 2020-12 (bounded subset) is the
  single normative machine grammar; no CDDL companion is maintained.
  The rejected alternative — dual CDDL/JSON-Schema grammars — buys
  IETF-native familiarity at the cost of dual-grammar drift, and this
  protocol's wire audience is not CBOR-bearing. *Revisit when:* an
  interop target this protocol must satisfy normatively requires CDDL,
  or the JSON-bearing ecosystem consolidates elsewhere.
- **B3 — dialect pin.** The pinned dialect is 2020-12, not a legacy
  draft: 2020-12 is the current published version, and the in-process
  IETF draft keeps it as the dialect meta-schema. *Revisit when:* a
  next JSON Schema version is published with breaking changes beyond
  the announced continuity scope.

A fourth standing watch (not a bet, a monitor): key-transparency work
in the IETF keytrans WG (architecture and protocol drafts, neither yet
an RFC) plus the Certificate Transparency v2 precedent (RFC 9162)
suggest that standardized key-history transparency will mature in this
window. CAP's descriptor histories are structured so a future
keytrans-conformant log can be adopted as a distribution layer without
changing artifact grammar. No action is taken until those drafts reach
RFC.
