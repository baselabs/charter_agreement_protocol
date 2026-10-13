# ML-DSA admission: the revision-3 registry change

Date: September 14, 2026

## Status

Accepted. Governs `protocol_revision` 3. This record covers the decisions visible on
the wire.

Amended September 15, 2026. OTP's `:crypto` verifies `mldsa44/65/87` from OTP 28.1
only when the runtime links OpenSSL 3.5 or later, since FIPS 204 support landed in
OpenSSL 3.5.0. Precompiled OTP builds link the operating system's `libcrypto.so.3`
dynamically, so on Ubuntu 24.04 (OpenSSL 3.0.x) they can neither generate nor verify
ML-DSA. No decision changes. Decision 8's declared floor is corrected to OTP 28.1 or
later with OpenSSL 3.5 or later linked, and CI runs the full check suite on
ubuntu-26.04 (OpenSSL 3.5.x). The corpus and the verdicts are unchanged.

## Context

Revision 2 settled the alg-name question for the classical operation. RFC 9864
deprecates the polymorphic `EdDSA` name, CAP mints the fully specified `Ed25519`
name, and the per-artifact binding rule ties every name to a minimum
`protocol_revision`. But both registry rows verify with Ed25519 keys (`algorithm.ex`
carries `key_algorithm: "Ed25519"` twice). So the agility that `spec/evolution.md`
describes (data-driven dispatch, a second key grammar, a second cryptographic
primitive) had never been exercised. Revision 2 changed only a name.

The migration target had been named since the specification was written: ML-DSA
(FIPS 204), registered for JOSE and COSE by RFC 9964 (Proposed Standard, May 2026) as
`ML-DSA-44`, `ML-DSA-65` and `ML-DSA-87`. That means pure ML-DSA only, `ctx` fixed to
the empty string, keys of 1312, 1952 and 2592 bytes, and signatures of 2420, 3309 and
4627 bytes. NIST IR 8547 says ML-DSA "can and should be put into use now". CNSA 2.0
requires ML-DSA-87 for signatures in national security systems by 2030 to 2033. RFC
9958 (PQUIP) gives guidance for adding post-quantum signatures to a protocol.

The runtime was ready. OTP's `:crypto` verifies `mldsa44/65/87` from OTP 28.1 with raw
public-key bytes, including signatures that Node generated. Node's built-ins cover all
three parameter sets from the 24.6 to 24.8 minor releases.

## Decision

Revision 3 carries exactly one semantic change, ML-DSA admission, made as the registry
and revision change that the no-versioning rule and `spec/evolution.md` describe.
There is no parallel artifact family, media type or header shape.

1. **Registry rows.** The closed alg registry gains three rows:
   `{name: "ML-DSA-44", min_protocol_revision: 3, key_algorithm: "ML-DSA-44"}`, and the
   same for `ML-DSA-65` and `ML-DSA-87`. The accepted revision set becomes {1, 2, 3},
   and unknown revisions still fail closed. The binding rule applies unchanged:
   `ML-DSA-*` at revisions 1 and 2 is rejected, since no conforming producer could
   have minted the pair, and any name at revision 4 or higher is still rejected.
2. **Per-name bounds are registry data.** Each row carries the exact public-key and
   signature byte lengths for its key algorithm (Ed25519: 32 and 64; ML-DSA-44: 1312
   and 2420; ML-DSA-65: 1952 and 3309; ML-DSA-87: 2592 and 4627). The framing layer
   checks the signature length for the row after parsing the protected header
   (revision 2's fixed 64-byte check ran before `alg` was known). `verify_signature`
   dispatches on the row's `key_algorithm`. The producer frames its provisional
   all-zero signature at the row's length, and `assemble_compact/2` accepts the row's
   length, not the literal 64. ML-DSA strictness is exactly the per-name byte lengths.
   The Ed25519 encoding checks apply to the Ed25519 rows only.
3. **Key grammar, gated one layer down exactly as the name was.** Descriptor
   `verification_keys[].algorithm` widens to the closed set {`Ed25519`, `ML-DSA-44`,
   `ML-DSA-65`, `ML-DSA-87`}. The `public_key` member's byte length is bound to the
   sibling `algorithm` member: the schema bounds the length to the union of legal
   encodings, and the codec binds the exact length, the key algorithm and the
   descriptor's `protocol_revision` together. **A revision-2 descriptor carrying an
   ML-DSA key is rejected.** Widening the key grammar without tying it to revision 3
   would widen a published revision's grammar after the fact. That is the
   set-widening alternative revision 2 rejected, one layer down.
4. **Mixed-algorithm key sets are legal.** The envelope `alg` is set by the signing key
   actually used. Descriptor N+1 may declare ML-DSA keys while being signed with an
   Ed25519 key active in N. That overlap lets a party rotate from classical to
   post-quantum keys inside one continuous history. The predecessor-binding rule is
   unchanged, and a mixed set is still one descriptor lineage.
5. **Emission.** Producers mint exactly the pairs (`Ed25519`, revision 2) and
   (`ML-DSA-65`, revision 3). The signing-input shape widens to
   `%{"kid" => ..., "claims" => ..., "algorithm" => ...}`, with the third member
   optional and defaulting to `Ed25519`. The chosen name selects the emission revision,
   the provisional signature length and the length `assemble_compact/2` accepts. The
   mint contract still holds by construction: the provisional decode runs the full
   binding rule against the framed bytes.
6. **Verifiers accept more than producers mint, on purpose.** Verifiers accept all
   three parameter sets from revision 3, so a counterparty aligned with CNSA 2.0 that
   mints ML-DSA-87 is not rejected by a CAP verifier. Minting stays at ML-DSA-65 (NIST
   category 3), so the emission contract
   stays a closed set of pairs. This mirrors revision 2, which accepts `EdDSA` and
   mints `Ed25519`. Minting ML-DSA-87 for CNSA reasons is a choice for a signer
   profile, never a CAP registry change.
7. **Cross-revision composition is unchanged.** Acceptance-claim equality never
   compares `protocol_revision`. A revision-3 ML-DSA acceptance anchors a revision-2 or
   revision-1 charter exactly as revision-2 acceptances anchor revision-1 charters.
8. **Runtime floors become declared facts.** OTP 28.1 or later, because the corpus
   gains ML-DSA cases, and byte-identical reports between the repository and the
   unpacked package rule out cases that depend on the runtime, so the package's own
   checks need it. The Node floor rises to the probed minor release that supports the
   verifier's calling convention. Both are stated in the README and the CHANGELOG and
   tested in CI at the floor. (Amended September 15, 2026: the floor also requires the
   runtime to link OpenSSL 3.5 or later. See the Status section.)

## Consequences

- Verdict changes. Nothing that verified before stops verifying. Newly accepted, on
  purpose: (`ML-DSA-44/65/87`, revision 3); (`EdDSA`, revision 3), which had been a
  fail-closed corpus case, so its expectation was rewritten and the unknown-revision
  case moved to revision 4; (`Ed25519`, revision 3); and mixed-revision views that
  include ML-DSA acceptances. Still rejected: (`ML-DSA-*`, revisions 1 and 2);
  (`Ed25519`, revision 1); any name at revision 4 or higher; HashML-DSA and `Ed448`
  names; case-changed names; ML-DSA keys in revision-2 descriptors; ML-DSA keys and
  signatures of the wrong length.
- Corpus. It gains the ML-DSA population (the primary mint `(ML-DSA-65, 3)`, a
  descriptor that bridges to mixed keys, and a mixed-revision view), the per-name
  negative cases above, and the revision-4 fail-closed case. The legacy `(EdDSA, 1)`
  fixtures stay pinned literally. New named source mutations cover the binding rows
  and the key-grammar check. The per-name length pre-checks have no mutation of their
  own, because the crypto layer rejects wrong-length input with the same code. They
  stay as bounds on work done before the cryptographic call.
- Identities. `corpus_digest`, `index_sha256_base64url` and `spec_digest` are recorded
  again (spec/core.md's Ed25519-specific signature text generalizes to the registry,
  and the migration-target section of `spec/evolution.md` becomes the record of this
  change). The extension `registry_digest` does not change.
- Artifact size. An ML-DSA-65 descriptor key is about 61 times the size of an Ed25519
  key, and a signature about 52 times. A 32-key ML-DSA-87 descriptor is about 113 KB of
  canonical JSON. The package release carrying revision 3 also adds the byte-weighted
  bound on the whole input and re-verification of an already verified context (no
  chain re-verification per acceptance), so the resource limits fit post-quantum
  artifact sizes, not Ed25519-era ones.
- Downstream. The companion signer releases alongside (RFC 9964 `priv` is the 32-byte
  seed, `ctx` is empty, and hedged signing is recommended; verification does not
  depend on it). The signer adopts the new CAP release in a reviewed release of its
  own.
- Requirement identifiers. The statement of `CAP-SIGNATURE-ed25519-verification`
  generalizes to "verify under the algorithm the registry row names", with its
  evidence checked again across both populations. No requirement ID is renamed.

## Rejected alternatives

- **Deferring ML-DSA under the revisit triggers in `spec/evolution.md`.** Those
  triggers (composite-signature RFCs, `EdDSA` becoming Prohibited) are external and
  had not fired. Admitting a second key algorithm is what the registry design exists
  for, and without one the agility that `spec/evolution.md` describes stays untested.
- **Splitting the hardening work and ML-DSA across two releases.** That means two
  rounds of recording identities again and two chances for the pinned legacy fixtures
  to drift, for the same end state.
- **A full dispatch-table registry at revision 2** (rejected in the revision-2 record
  too). Revision 3 is the change that gives the row shape real differences to carry,
  so the machinery lands now, with two key grammars and two crypto primitives to show
  it works.
- **Adopting post-quantum composites or hybrids.** They are still Internet-Drafts. The
  standing position in `spec/evolution.md` (add pure ML-DSA beside Ed25519, which stays
  accepted, and revisit composites when one becomes an RFC) is unchanged.

## Revisit triggers

- A composite-signature RFC reaching Proposed Standard. It would use the same
  registry slot, through the same kind of registry and revision change.
- `EdDSA` moving from Deprecated to Prohibited in the JOSE registry. A later revision
  drops the row; the question of existing artifacts is recorded there, not here.
- Changes to HashML-DSA registration in JOSE. HashML-DSA is outside RFC 9964's scope
  today. Admitting it later is a new change, never a widening of the pure names.
