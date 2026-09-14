# ML-DSA admission: the revision-3 registry act

Date: 2026-09-14

## Status

Accepted. Governs `protocol_revision` 3. Input design: the scoped release spec at
`.kimosabe/specs/2026-09-14-cap-0.3.0-revision-3-ml-dsa-release.md`, itself backed
by substrate probes (executed 2026-09-14 on the CI-pinned Elixir 1.20.3 / OTP 29.0.3
/ Node 24.18.0), an independent adversarial design pass, and a full 0.2.1 audit.
This ADR records the wire-visible decisions; the audit-remediation items riding the
same package release are engineering work, not ADR scope.

## Context

Revision 2 closed the alg-name question for the classical operation: RFC 9864
deprecates the polymorphic `EdDSA` name, CAP mints the fully-specified `Ed25519`
name, and the per-artifact binding rule ties every name to a minimum
`protocol_revision`. But both registry rows verify with Ed25519 keys
(`algorithm.ex` carries `key_algorithm: "Ed25519"` twice), so the agility mechanism
`spec/evolution.md` advertises — data-driven dispatch, second key grammar, second
cryptographic primitive — has never been exercised. Revision 2 was a name-only act.

The migration target has been named since the spec set was written: ML-DSA
(FIPS 204), registered for JOSE and COSE by RFC 9964 (Proposed Standard,
May 2026) as `ML-DSA-44`, `ML-DSA-65`, `ML-DSA-87` — pure ML-DSA only, `ctx`
fixed to the empty string, keys 1312/1952/2592 bytes, signatures 2420/3309/4627
bytes. NIST IR 8547 directs that ML-DSA "can and should be put into use now"
(quantum-vulnerable algorithms, including EdDSA, deprecated ~2030, disallowed
~2035); CNSA 2.0 requires ML-DSA-87 for signatures in national security systems
by 2030–2033; RFC 9958 (PQUIP) publishes the engineer guidance a protocol reviewer
will apply. A protocol entering external standardization in late 2026 with one
classical-only algorithm and a paper migration plan answers its first question
with a promise; revision 3 answers it with a diff.

The substrate is ready: OTP's `:crypto` verifies `mldsa44/65/87` from OTP 28.1
(raw public-key bytes — probed cross-implementation against Node-generated
signatures; ML-DSA-65 verify ≈ 1.9× an Ed25519 verify, no cliff), and Node's
builtins cover all three parameterizations from the 24.6–24.8 minors.

## Decision

Revision 3 carries exactly one semantic change — ML-DSA admission — implemented
as the registry-and-revision act the no-versioning rule and `spec/evolution.md`
define. No parallel artifact family, media type, or header shape.

1. **Registry rows.** The closed alg registry gains three rows:
   `{name: "ML-DSA-44", min_protocol_revision: 3, key_algorithm: "ML-DSA-44"}`,
   and likewise `ML-DSA-65`, `ML-DSA-87`. The accepted revision set becomes
   `{1, 2, 3}`; unknown revisions still fail closed. The binding rule applies
   unchanged: `ML-DSA-*` at revisions 1–2 is rejected — no honest producer could
   have minted the pair — and (everything, revision ≥ 4) stays red.
2. **Per-name bounds are registry data.** Each row carries the exact public-key
   and signature byte lengths for its key algorithm
   (Ed25519: 32/64; ML-DSA-44: 1312/2420; ML-DSA-65: 1952/3309; ML-DSA-87:
   2592/4627). The framing layer enforces the signature length per row AFTER
   protected-header parse (revision 2's fixed 64-byte check ran before `alg` was
   known); `verify_signature` dispatches on the row's `key_algorithm`; the
   producer frames its provisional zero-signature at the row's length; and
   `assemble_compact/2` accepts the row's length, not the literal 64. ML-DSA
   strictness is exactly the per-name byte lengths — lattice schemes have no
   torsion/small-order surface, and the Ed25519 non-canonical-encoding pre-checks
   remain Ed25519-row behavior.
3. **Key grammar, gated one layer down exactly as the name was.** Descriptor
   `verification_keys[].algorithm` widens to the closed set
   {`Ed25519`, `ML-DSA-44`, `ML-DSA-65`, `ML-DSA-87`}; the `public_key` member's
   byte length is bound to the sibling `algorithm` member (the schema bounds
   length to the union of legal encodings; the codec binds the exact length, the
   key algorithm, and the descriptor's `protocol_revision` together). **A
   revision-2 descriptor carrying an ML-DSA key rejects** — widening the key
   grammar without gating it on revision 3 would retroactively widen a published
   revision's grammar, the "pure set-widening" alternative revision 2 rejected,
   reincarnated one layer down.
4. **Mixed-algorithm key sets are legal.** Envelope `alg` is determined by the
   signing key actually used. Descriptor N+1 may declare ML-DSA keys while being
   Ed25519-signed by a key active in N — the bridge/overlap transition that lets
   a party rotate classical→PQ inside one continuous history. The predecessor-
   binding rule is unchanged; a mixed set is still one descriptor lineage.
5. **Emission.** Producers mint exactly the pairs (`Ed25519`, revision 2) and
   (`ML-DSA-65`, revision 3). The signing-input input shape widens to
   `%{"kid" => …, "claims" => …, "algorithm" => …}` (the third member optional,
   defaulting to `Ed25519`); the chosen name selects the emission revision, the
   provisional signature length, and the assemble length. The by-construction
   mint enforcement survives: the provisional decode still runs the full
   binding rule against the framed bytes.
6. **Acceptance vs minting asymmetry is deliberate.** Verifiers admit all three
   parameterizations from revision 3 — a CNSA 2.0-aligned counterparty minting
   ML-DSA-87 must not be redded by a CAP verifier. Minting stays closed at
   ML-DSA-65 (NIST category 3, comfortably above Ed25519's classical strength)
   so the emission contract remains a closed pair set, mirroring revision 2's
   accept-EdDSA/mint-Ed25519 pattern. CNSA-constrained minting of ML-DSA-87 is
   a signer-profile decision, never a CAP registry act.
7. **Cross-revision composition is unchanged.** Acceptance-claim equality never
   compares `protocol_revision`; a revision-3 ML-DSA acceptance anchors a
   revision-2 or revision-1 charter exactly as revision-2 acceptances anchor
   revision-1 charters today.
8. **Runtime floors become declared facts.** OTP ≥ 28.1 (the corpus gains
   ML-DSA cases, and repository/unpacked-package report byte-identity forbids
   runtime-conditional cases, so the package's own gates need it) and the Node
   floor rises to the probed minor that satisfies the verifier's calling
   convention. Both are stated in the README and CHANGELOG and matrix-tested in
   CI at the floor.

## Consequences

- Verdict audit. Nothing green→red. Red→green, deliberate: (`ML-DSA-44/65/87`,
  revision 3); (`EdDSA`, revision 3) — currently a certified fail-closed corpus
  case, whose expectation is rewritten while the unknown-revision duty re-mints
  at revision 4; (`Ed25519`, revision 3); mixed-revision views including ML-DSA
  acceptances. Stays red: (`ML-DSA-*`, revisions 1–2); (`Ed25519`, 1);
  (`anything`, ≥ 4); HashML-DSA and `Ed448` names; case-mutated names; ML-DSA
  keys in revision-2 descriptors; wrong-length ML-DSA keys and signatures.
- Corpus: the ML-DSA population (primary mint `(ML-DSA-65, 3)`, mixed-key
  bridge descriptor, mixed-revision view), the per-name negatives above, and
  revision-4 fail-closed — legacy `(EdDSA, 1)` fixtures stay literally pinned.
  Named mutations join the battery for the binding rows and the key-grammar
  gate; the pinned mutation list in the release gate moves in lockstep. The
  per-name length pre-checks earned no mutation of their own: the seeded
  mutation survived because the crypto layer already rejects wrong-length
  inputs with the same code — verdict-redundant by the revision-2 ADR's
  dead-logic discipline, the checks remain as pre-crypto work bounds.
- Identities: `corpus_digest`, `index_sha256_base64url`, `spec_digest` re-pin
  (spec/core.md's Ed25519-specific signature prose generalizes to the registry;
  `spec/evolution.md`'s migration-target section becomes the record of the act).
  The extension `registry_digest` is unaffected.
- Artifact scale: an ML-DSA-65 descriptor key is ~61× an Ed25519 key and a
  signature ~52×; a 32-key ML-DSA-87 descriptor is ~113 KB canonical. The
  package release carrying revision 3 also lands the byte-weighted aggregate
  input budget and verified-context re-verification (no per-acceptance chain
  re-verification), so the resource boundary is calibrated for PQ-sized
  artifacts, not Ed25519-era sizes.
- Downstream: the companion signer releases alongside (RFC 9964 `priv` is the
  32-byte seed; `ctx` empty; hedged signing recommended — verification is
  agnostic). Its deliberate-bump wall governs adoption.
- Requirement identifiers: `CAP-SIGNATURE-ed25519-verification`'s statement
  generalizes to "verify under the algorithm the registry row names" with its
  evidence re-certified across both populations; no requirement ID is renamed.

## Rejected alternatives

- **Deferring ML-DSA under `spec/evolution.md`'s revisit triggers** — the
  triggers (composite-sig RFCs, EdDSA Prohibited) are external and unfired, but
  the operative bar was already met: the standards submission is itself the
  event that makes the migration expected, and deferral ships the untested
  agility claim into the review that will probe it.
- **Splitting hardening and ML-DSA across two releases** — two full
  recertification cycles, two chances to drift the pinned legacy fixtures, and
  a PQ story one release later, for an end state reviewers evaluate identically.
  Recorded as the fallback had the producer/floor seams proved blocking; they
  did not.
- **A full dispatch-table registry at revision 2** (carried forward from the
  revision-2 ADR's rejection) — revision 3 is the act that makes the row shape
  carry real differences; the machinery lands now, with two key grammars and
  two crypto primitives to prove it.
- **Adopting PQ composites or hybrids** — still Internet-Drafts;
  `spec/evolution.md`'s standing decision (land pure ML-DSA alongside
  still-accepted Ed25519; revisit composites when one reaches RFC) is unchanged.

## Revisit triggers

- A composite-signature RFC reaching Proposed Standard: lands in the same
  agility slot by the same registry-and-revision act.
- `EdDSA` moving Deprecated→Prohibited in the JOSE registry: a future revision
  drops the row; the pre-existing-artifact policy question is recorded there,
  not here.
- HashML-DSA registration changes in JOSE: currently out of scope of RFC 9964;
  any future admission is a new act, never a widening of the pure names.
