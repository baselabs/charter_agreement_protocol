# Algorithm-name agility: the revision-2 alg change

Date: August 26, 2026

## Status

Accepted. Governs `protocol_revision` 2.

The producer has no separate check of the revision it emits. The binding rule,
applied when the producer decodes its own provisional artifact, already makes it
impossible for the producer to build a non-conforming artifact.

## Context

RFC 9864 ("Fully-Specified Algorithms for JOSE and COSE", Proposed Standard, October
2025) registers the fully specified JOSE alg names `Ed25519` and `Ed448` and marks the
polymorphic `EdDSA` registration **Deprecated**. Deprecated is not prohibited:
existing use stays valid, but new registrations must be fully specified, and the
registry's direction is clear.

CAP revision 1 closed the protected header's `alg` to exactly `EdDSA` (spec/core.md,
protected header; `spec/schemas/compact-jws-protected-header.json`). The descriptor key
grammar already named keys by the fully specified `algorithm: "Ed25519"`. The split in
naming is only JOSE registration history. RFC 9864's `Ed25519` is exactly the
operation CAP already performed: the same curve and the same signature. Keys are
closed to 32-byte Ed25519 with no Ed448 path, so there is no second cryptographic
operation.

A new protocol entering standardization while minting a deprecated identifier invites
the same review comment every time. The event that would make the change urgent
(`EdDSA` moving from Deprecated to Prohibited, or verifiers refusing it) would arrive
after adoption, as changed verdicts on live artifact chains. At the time only the
maintainer's own projects used CAP, so the change was cheapest then.

## Decision

Revision 2 carries exactly one semantic change, the alg-name contract:

1. **The binding rule, per artifact, not per view.** Decoders accept `alg: "EdDSA"` at
   any accepted `protocol_revision`. `alg: "Ed25519"` requires `protocol_revision` 2 or
   higher. The accepted revision set is {1, 2}, and unknown revisions fail closed. An
   artifact carrying `Ed25519` at revision 1 is rejected: no conforming producer could
   have minted it, since revision 1's specification pinned `EdDSA`, and rejecting it
   is what gives the corpus's per-name negative cases their meaning.
2. **Emission.** The signing-input producer emits exactly (`"Ed25519"`,
   `protocol_revision` 2). Revision-1 `EdDSA` artifacts stay verifiable under the
   full profile; a release that stopped accepting them would change verdicts, so the
   verification semantics version would record it. Nothing new mints a deprecated
   name.
3. **Cross-revision composition.** Artifacts mix freely within a view. A revision-2
   acceptance may anchor a revision-1 charter revision, because charters outlive
   protocol revisions. The TypeScript verifier's acceptance-revision equality
   (`core.ts`, `acceptanceFromCompact`) is replaced by the accepted-set semantics, and
   the TypeScript verifier gains the revision-range check it never had.
4. **The closed set is the registry.** Each implementation keeps one closed set, with
   one source, whose rows have the shape `{name, min_protocol_revision, key_algorithm}`.
   For revisions 1 and 2 the `key_algorithm` column is `Ed25519` for both rows. This
   set is the data-driven algorithm registry that `spec/evolution.md` describes. A
   later algorithm is added the same way, with a new row plus the key grammar its
   column requires, never by forking the code path. ML-DSA (RFC 9964) was added this
   way at `protocol_revision` 3.
5. **Decoded structs carry the real revision.** Every codec's extraction carries the
   artifact's actual `protocol_revision`. The revision-1 code had hard-coded the
   literal 1.

## Consequences

- Verdict changes. Nothing that verified before stops verifying. Newly accepted:
  (revision 2, `Ed25519`), the intended class; (revision 2, `EdDSA`), the
  compatibility case, so a producer that bumps the revision before renaming its
  emission does not break; and mixed-revision views. (Revision 1, `Ed25519`) is still
  rejected.
- Conformance corpus. Regenerated with both populations: (revision 1, `EdDSA`) legacy
  fixtures, (revision 2, `Ed25519`) primary, (revision 2, `EdDSA`) compatibility, and
  the mixed-revision acceptance view, plus negative cases: (revision 1, `Ed25519`),
  unknown and case-changed names, and revision 3 as the fail-closed case across
  implementations. **The legacy fixtures pin revision 1 and `EdDSA` literally, on
  purpose.** They are built independently of the code that mints new artifacts.
  Rewriting them to read the shared constant would turn the legacy population into a
  copy of the current code and remove its value as evidence.
- Identities. The binding rule changed the specification and the corpus, so
  `corpus_digest`, `index_sha256_base64url` and `spec_digest` changed. The extension
  `registry_digest` did not.
- Downstream. `charter_agreement_signer` adopts a new CAP release only in a release
  of its own, so adopting revision 2 needed a signer release.

## Rejected alternatives

- **A full dispatch-table registry now.** Two rows that differ only in name give a
  table nothing to dispatch. The next algorithm (ML-DSA) changes key grammar and
  bounds, so it was never a one-row append. The row shape is adopted; the table
  machinery is not.
- **Widening the set without the binding rule.** Both names would be legal at both
  revisions, the per-name negative cases would shrink to spelling changes, and CAP
  would accept a class no conforming revision-1 producer could mint.
- **Keeping the TypeScript acceptance-revision equality.** It would quietly reopen
  the settled rule that revisions mix. The first real acceptance of an existing
  charter after the cutover would verify in Elixir and fail in TypeScript, and a
  counterparty would find it before a test did.

## Revisit triggers

- `EdDSA` moving from Deprecated to Prohibited in the JOSE registry. A later revision
  drops the `EdDSA` row. Whether existing artifacts stay verifiable is that revision's
  policy question, recorded here and not decided.
- ML-DSA adoption (RFC 9964). Done at `protocol_revision` 3 through the same kind of
  registry and revision change; see [ML-DSA admission](ml-dsa-admission.md).
- A third alg-name class appearing in the JOSE registry: the same kind of change.
