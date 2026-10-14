# Changelog

All notable public changes to `charter_agreement_protocol` are documented here.

## [Unreleased]

### Security

- **Two Ed25519 public key encodings were accepted.** Releases 0.3.0 through
  0.5.0 accepted the keys `0100000000000000000000000000000000000000000000000000000000000080`
  and `ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` (x = 0
  with the sign bit set). Under either key, a signature computed without a
  private key verifies. 0.6.0 decodes every Ed25519 public key and signature
  `R` as a curve point and rejects a value that is not canonical, is not a
  curve point, or has small order. Releases 0.1.0 and 0.2.x rejected both
  encodings. See the errata and the upgrade guide for how to check stored
  results.

### Added

- `prepare_signing/5`, `finish_signing/2` and `SigningPlan` check the holder's
  descriptor key before external signing and verify the finished compact.
- `signing_key_invalid` and `signing_key_mismatch` name snapshot failures.
- The `signing.prepare` corpus surface pins segments, key status and errors.
- Corpus cases pin JSON check order, empty revision views and float token types.

### Fixed

- Corpus runners return typed errors for malformed inputs and contexts,
  including zero limits for governing queries and receipts without a context.
- Revision projections support an empty binding list.
- Missing corpus profile axes use the full axis; explicit null axes return
  `invalid_profile` on every surface.
- Ed25519 public keys are now fully decoded on admission, so two more
  small-order encodings and keys that are not curve points are rejected.
- Malformed limits structs and improper profile algorithm lists return typed errors.
- Malformed retained context lists, envelope fields and nested structs
  return typed errors.
- The `receipt.verify` conformance runner honors a case's `limits`.
- Unknown corpus `limits` and `profile` members use the library's
  `invalid_limits` and `invalid_profile` codes.
- `Capability.report/0` handles raising provider calls. Declared support and
  known-answer verification are cached once per key algorithm.

### Changed

- Verification semantics moves to 6. Ed25519 admission now rejects the two
  remaining small-order encodings and keys that are not curve points, using
  the same point rule for the public key and signature `R`. Caller-built
  contexts with malformed field types now return `invalid_type` consistently.
  Receipt revision numbers, chain topology and `not_verified` entries,
  descriptor-chain topology and revision `supersedes` entries are checked. Some of these contexts returned
  `ok` in 0.5.0; others raised or returned a context-specific error.
  The 0.6.0 compatibility row records these transitions. Producer bytes stay
  unchanged.

### Repository-side

- ML-DSA test skips depend on runtime declarations. Every Ed25519 corpus
  case still runs when the runtime does not declare ML-DSA.
- A test-only fixture checks 1,300 strict Ed25519 primitive cases from BAP
  0.8.0, with byte hashes. It is excluded from the package and CAP corpus.
- Cost checks cover a final-signature failure and require zero pure
  exponentiations on a runtime with native modular exponentiation.
- `mix historical.check` replays the released 0.5.0 corpus (163 cases, no
  listed transitions).
- `mix verifier.source` checks the newest change of the TypeScript verifier
  pin on the first-parent history. It used to compare only with the pin at
  `HEAD`, so a committed backward pin passed in CI, where the working tree
  equals `HEAD`.

## [0.5.0] — 2026-10-13

One verdict change: a charter's parties must be distinct parties (see
Security). The verification semantics version moves from 4 to 5. Apart from
that change, this release gives the same verdict as 0.4.1 on every case of
the 0.4.0 and 0.4.1 corpora. Separately, a narrowed capability profile now
reaches the context a standalone call re-verifies, and a profile rejection
is reported under its own code. On a runtime that verifies every algorithm,
calls under the full profile are unaffected.

### Security

- Releases 0.1.0 through 0.4.1 accepted a charter in which one party held
  both roles, as long as an unrelated second key history was present in the
  view. "Every party accepted" could then be satisfied by a single party. Two
  checks now reject that:
  - a charter revision whose parties name the same descriptor fails to
    decode with `:revision_invalid`;
  - a chain view fails with `:chain_invalid` when a revision's parties
    resolve to the same key history, or when the view holds a key history
    that no revision names.

  To check charters you stored under an earlier release, re-verify them with
  this release, or look for a revision whose `parties` repeat a
  `party_descriptor_digest` and for any descriptor history the revisions do
  not name. The TypeScript verifier already rejected these views.
- Releases 0.4.0 through 0.4.1 applied a caller's narrowed capability
  profile only partly in `verify_acceptance/5`, `verify_termination/5` and
  `verify_receipt/4`. The supplied revision and descriptor history and the
  chain view a receipt names were verified under the full profile, and a
  receipt checked against a bare revision was not checked against the
  profile at all, so a profile that excluded an algorithm or a
  `protocol_revision` could still pass a call whose context or receipt used
  it. The profile now applies to every artifact these calls verify and fails
  with `:algorithm_outside_profile` or `:revision_outside_profile`. Acceptance
  and termination calls check the supplied revision first, then the
  descriptor history; a receipt call checks its chain view as
  `verify_chain/6` does, or its bare revision, then the receipt. If you rely
  on a profile to keep an algorithm or revision out, verify stored results
  from these calls again.
- Profile rejections were reported under another code in some cases. An
  acceptance, termination, descriptor or receipt outside the profile whose
  `kid` names no key failed with the key lookup code (`:acceptance_invalid`,
  `:termination_invalid`, `:descriptor_key_invalid`) or, for a receipt in a
  chain view, `:signature_invalid`; the envelope is now admitted before the
  key is looked up, so it fails with the profile code. `verify_descriptor/4` given a predecessor outside
  the profile failed with `:descriptor_chain_invalid`; it now fails with the
  profile code, as `verify_descriptor_chain/3` does, and a predecessor whose
  signature the runtime cannot check reports
  `:algorithm_unsupported_on_substrate`.

### Added

- `CharterAgreementProtocol.encode_charter_revision/1` builds a Charter
  Revision's canonical bytes from a plain claims map. It checks the result
  with the decoder verification uses, so invalid claims fail with the error a
  verifier would report.
- `Canonicalization.from_plain/1` converts a plain Elixir term (maps with
  string keys, lists, binaries, integers, floats, booleans and `nil`) to the
  tagged JSON form, and `Canonicalization.encode_plain/1` encodes it to the
  same bytes `Canonicalization.encode/1` gives for that tagged form. Floats
  stay floats. Any other term returns an `:invalid_type` error. You no longer
  need your own tagging helper to build claims.
- `priv/verifier-source.json` ships in the package. It names the TypeScript
  verifier repository and the commit this release was checked against, so
  you can match an npm verifier version to this release. For 0.5.0 that is
  the `@charter-agreement-protocol/verifier` 0.6.0 release commit.

### Conformance

- The conformance corpus grows from 104 to 163 cases. Apart from the two
  distinct-party cases and the 24 profile cases on single-artifact surfaces
  (which record the corrected profile behavior; 0.4.1 differs on most of
  them), each new case records a verdict this package already returned. A second implementation could pass the earlier 104 cases and still
  get these wrong. The new cases cover:
  - a verified termination closing the charter at its effective instant, for
    governing-revision selection and for receipts;
  - strict revision decoding: non-canonical bytes, a duplicate member, a
    precedence value outside the enumeration, an unparsable
    `effective_from`, an unknown `protocol_revision`, wrong member types, and
    one or three parties;
  - one extra member in acceptance, termination, receipt and descriptor
    claims;
  - descriptor histories grouped per party: a two-party descriptor set, a
    successor without `party_id`, and a chain view holding one party's
    history;
  - artifact sets exactly at each size limit and one past it;
  - the full indexed-price body and its receipt observation body;
  - a duplicate JSON member that is not the last member, and member order for
    integer-like keys;
  - a digest inside signed receipt claims spelled with non-canonical
    base64url;
  - an `effective_from` in year 0000, which RFC 3339 allows;
  - the distinct-party rule: one descriptor named for both roles, and one
    party's two descriptors holding both roles beside an unrelated history;
  - a narrowed profile on `party_descriptor.verify` (with a predecessor
    history), `acceptance.verify`, `termination.verify` and
    `receipt.verify`: each context artifact outside on each axis, the
    revision checked before the descriptor history, a receipt checked against
    a bare revision, artifacts outside the profile whose `kid` names no key,
    and a profile that names one axis only.
- The `party_descriptor.verify`, `acceptance.verify`, `termination.verify`
  and `receipt.verify` cases take an optional `profile` input; a
  `party_descriptor.verify` case may give `predecessor_compacts`, its
  predecessor history genesis first; and a `receipt.verify` case may give
  `revision_text` instead of `chain` as its context.
- The corpus now requires these case classes, so a later corpus cannot drop
  them: `invalid_encoding` and `non_canonical_bytes` on
  `charter_revision.decode`; `unknown_member` on `acceptance.verify`,
  `termination.verify` and `receipt.verify`; `exact_bound` and
  `maximum_plus_one` on `chain.verify`; `profile_narrow_valid`,
  `profile_algorithm_outside` and `profile_revision_outside` on
  `party_descriptor.verify`, `acceptance.verify`, `termination.verify` and
  `receipt.verify`; and a new
  class, `terminated`, on `governing_revision` and `receipt.verify`.
- The conformance runner passes a case's `limits` to chain views, as it
  already did for JSON decoding.
- The compatibility table (`ReleaseIdentity.compatibility/0` and
  `priv/release-metadata.json`) gains a row for 0.5.0: verification
  semantics 5, the new corpus digest, and one green-to-red transition (the
  distinct-party rule). A semantics family may now span more than one row,
  one per released corpus.

### Specification

- [CAP-CHAIN-distinct-parties]: a revision may not name one descriptor for
  two roles, a revision's parties must resolve to different key histories,
  and every key history in a view must be one a revision names.
- [CAP-PROFILE-context-admission]: a call that re-verifies caller-supplied
  context applies the caller's profile to every artifact in it.
- Two behaviors the reference already had are now normative requirements.
  [CAP-CHAIN-artifact-set-bounds]: each artifact list holds at most
  `max_artifact_set_items` items and the whole set at most
  `max_artifact_set_bytes` bytes, checked before any decode or signature
  check. [CAP-CHAIN-termination-closes]: a verified termination that names
  the revision governing at its `effective_at` closes the charter from that
  instant.
- The security and privacy considerations said every attached artifact is
  Ed25519 and every descriptor declares Ed25519 keys. Since
  `protocol_revision` 3 admitted ML-DSA, that was wrong. Both now name the
  registered algorithms (Ed25519, ML-DSA-44, ML-DSA-65 and ML-DSA-87) and
  point to core section 4.1. The `PartyDescriptor.VerificationKey` docs say
  the same.
- These changes alter specification bytes, so `spec_digest` moves.
  `spec/changelog.md` records each one.

### Changed

- The [upgrade guide](docs/guides/upgrading-verification-identity.md) no
  longer lists `spec_digest` among the values to compare when you replay
  stored verdicts. Record it, but compare `verification_semantics_version`,
  the explicit limits, `signature_registry_digest`, and each artifact's
  `protocol_revision` and `alg`. An editorial specification fix moves
  `spec_digest` without changing any verdict, while every verdict change
  moves the semantics version.

### Documentation

- The guides are rewritten for this release and organized as tutorials,
  how-to guides, explanations and reference. New pages: "Your first verified
  charter", "Produce and verify with the signer", "Integrate CAP into an
  application", "Handle errors" (the meaning of each error code and what the
  caller should do), "Implement CAP in another language", limits and
  profiles, a glossary and a cheatsheet. The upgrade guide is now on HexDocs.
- The recipes used `protocol_revision` 1, which the default Ed25519 producer
  refuses with `:signing_input_invalid`. They now use 2, and a test runs
  them.
- Both notebooks install the package from Hex and open from HexDocs with
  "Run in Livebook". The charter tour produces its artifacts with
  `charter_agreement_signer`.
- The API reference documents every facts struct's fields and gives examples
  for the main module's functions. Internal modules no longer appear.
- `docs/protocol.md` and `docs/test-vectors.md` are merged into the
  reference and implementer pages.

### Repository-side

- The checks that compare the two implementations now run the TypeScript
  verifier's own repository at the commit in `priv/verifier-source.json`.
  The in-tree `verifier/` copy had drifted from the npm package and is
  removed. `mix verifier.source` fetches and checks the pinned commit.
- The JSON-decoder differential check could not fail on its deliberately
  broken TypeScript copy; now it can. Its generated input now includes
  integral floats written with a fraction or exponent. One helper,
  `scripts/seeded_mutation.exs`, applies every such edit and requires its
  anchor text to occur exactly once.
- The named source mutations grow from 26 to 43. New: `termination-close-ignored`,
  `revision-canonical-bytes-skip`, `artifact-set-bytes-ceiling-skip`,
  `distinct-descriptors-skip`, `party-histories-skip`,
  `two-party-history-count-relaxed`, `context-descriptor-profile-skip`,
  `context-revision-profile-skip`, `context-order-swapped`,
  `termination-order-swapped`, `termination-descriptor-profile-skip`,
  `chain-receipt-context-profile-skip`, `chain-receipt-admission-skip`,
  `revision-only-receipt-profile-skip`, `predecessor-profile-code-swallowed`,
  `descriptor-admission-before-key-skip` and `profile-revision-gate-defeat`.
  `profile-gate-defeat` now targets the admission rule itself, since every
  caller admits the envelope before it looks a key up.
- `mix historical.check` adds the v0.4.0 and v0.4.1 corpora (104 cases
  each, no listed transitions).
- CI runs on Linux only and skips pushes that change only documentation.

## [0.4.1] — 2026-09-24

Packaging-correction release; `lib/` is byte-identical to 0.4.0 and the
certified corpus, census digest, and semantics identity (4) are unchanged.

### Fixed

- `docs/adr/release-identity.md` now ships in the archive: three
  in-package files referenced it (the errata policy's immutability
  statement, the no-versioning rule's two approved boundary exceptions,
  and the issued consumer transition contract) but the 0.4.0 file list
  omitted it, leaving dangling references in-archive.
- `package.secret_scan.ignore` for the two deterministic public
  test-data surfaces (the known-answer vectors in `capability.ex` and
  the signed conformance corpus): hex.pm's published-package scanner
  does not read repository-level scanner config, and its 0.4.0 scan
  reported a 40-character interior substring of the public ML-DSA-87
  known-answer signature as a `github-app-token` — a `ghs_` collision
  inside a base64url blob whose run continues past the match, not a
  credential (nothing to revoke). The ignore is hex's documented
  mechanism and ships in this release's mix.exs.

### Repository-side (not shipped)

- The corrupt-public-key test's zero-overwrite corruption became a no-op
  whenever key generation emitted a leading zero byte (1-in-256; a CI
  lane drew it); it now XORs the byte with 0xFF. No production change.

## [0.4.0] — 2026-09-24

The release-identity act: a versioned, machine-readable identity contract;
honest substrate capability; the capability profile; revision exposure in
facts; and the standing historical certification. Judged design of
2026-09-23 (two adversarial review lenses plus an independent judge);
owner rulings 2026-09-24. No wire change — `protocol_revision` stays 3.

### Release identity (public contract, additive)

- The release manifest is now a versioned contract: `manifest_version`,
  `verification_semantics_version`, `limits{default,maximum}`,
  `signature_algorithms` + `signature_registry_digest` (the signature
  registry's own domain-separated identity — the extension registry's
  digest never identified signature algorithms), and a machine-readable
  `compatibility` matrix. Additive-only; consumers MUST ignore unknown
  members; the release-candidate gate now asserts the manifest equals the
  live data-in-code functions member by member (the archive pin
  authenticated bytes, not truth).
- The verification-semantics identity is the STRICT verdict-function
  identity (admissions and limits-default changes count; subjects,
  substrate outcomes, crash-to-typed conversions, and facts fields do
  not). Retroactive mapping published: S1=0.1.0, S2=0.2.0–0.2.1,
  S3=0.3.0–0.3.2, S4=0.4.0, each family's transitions enumerated
  (`ReleaseIdentity.verification_semantics_history/0`).
- A standing per-release historical differential gate joins the quality
  battery: every frozen certified corpus (v0.1.0 85, v0.2.0/0.2.1 90,
  v0.3.0/0.3.2 100 cases) runs under the current package with verdict
  agreement required except an enumerated per-(tag, case) allowlist —
  red-provable by allowlist mutation (observed: a flipped transition
  direction fails the gate). The corpus loader gains an explicit historical mode that keeps every
  released-artifact integrity check and relaxes only the compiled
  applicability floor and the current extension-registry identity.
- The consumer transition contract is ISSUED
  (docs/guides/upgrading-verification-identity.md): no protocol-side act
  preserves a persisted tuple that includes package version or census
  digests; the verification-identity tuple to persist instead is named
  and warranted; the pinning mechanics are stated; the consumer rehearsal
  lane is accepted as published consumer evidence outside the certified
  corpus.

### Capability honesty

- `capabilities()` — one verifiable verdict per registry row, derived
  from pinned known-answer verification vectors gated on the runtime's
  declared public-key algorithms; linked-crypto identity informational
  only. The TypeScript verifier mirrors it with the same pinned bytes
  and the same registry identity (`algorithmRegistryDigest()`).
- `:algorithm_unsupported_on_substrate`: the named implementation-local
  diagnostic for verification that is impossible for substrate reasons —
  replacing exactly the capability conjunct, after every deterministic
  check (a forged artifact never earns a retryable diagnosis), on the
  Ed25519 row as well, with a known-answer re-run disambiguating a
  raising crypto call (substrate obstacle vs. bad input), propagated
  through every aggregator including the receipt path's
  exact-one-verifier partition. Deliberately OUTSIDE the conformance
  verdict surface and cross-verifier report identity; its real-substrate
  evidence is the new capability-limited CI lane (Ubuntu 24.04 / OpenSSL
  3.0.13, always green). OBSERVED on that substrate: OTP 28.5 and 29.1
  both report no `:mldsa*` atoms — the diagnostic is reachable exactly
  where it was asked for.

### Capability profile

- `CharterAgreementProtocol.Capability.Profile` — caller-supplied pure
  data (`new/1`, `valid?/1`, `full/0`), validated like `Limits` at every
  verify surface, failing closed with `:invalid_profile` before
  verification begins. Two axes (envelope `alg` names;
  `protocol_revision` range) applied per artifact and threaded through
  every verify seam (`verify_chain/6` and per-artifact profile arities
  on the facade), never a pre-pass. Out-of-profile artifacts reject
  BEFORE crypto with `:algorithm_outside_profile` /
  `:revision_outside_profile` — through the receipt aggregator's
  partition too. Declared key material is deliberately unconstrained (a
  revision-3 descriptor declaring ML-DSA keys, signed by an active
  Ed25519 key, is in profile for an Ed25519-only deployment; exclude
  ML-DSA-keyed lineages by narrowing the revision axis).

### Verification output and the timestamp floor

- Every facts record carries its artifact's `protocol_revision`, and the
  SIGNED artifacts' records carry the envelope `alg` — `ReceiptFacts`
  included (it embeds no decoded artifact; the scalars are the only
  route). Unsigned revision facts carry no `alg` (there is no envelope);
  the field is nil by design. Keys land with defaults and a
  construction-site gate makes a missed site loud instead of a runtime
  red.
- `PartyDescriptor.effective_from` gains the 1..64 string-byte floor its
  seven sibling timestamp members took in 0.3.0 — the last live timestamp
  asymmetry, closing semantics S3 and opening S4. Its green-to-red
  transition is a certified corpus witness
  (`descriptor-effective-from-timestamp-floor`).

### Conformance

- Certified corpus re-recorded at 104 cases: the `chain.verify_profile`
  surface (both out-of-profile axes red, an in-profile narrowing green)
  and the timestamp-floor witness. The `profile-gate-defeat` mutation
  joins the battery (26 named mutations, all red-proved; the corpus test
  executes the profile cases directly so the mutation cannot survive).
  TypeScript verifier agreement is byte-identical over the new corpus.

## [0.3.2] — 2026-09-16

Toolchain-and-hygiene release; no wire-visible or behavioral library change
(`lib/` is byte-identical to 0.3.1).

### Fixed

- Both shipped notebooks (charter tour, fork repair) minted their
  Ed25519-signed artifacts with `protocol_revision => 1`; the registry
  admits the Ed25519 key grammar from revision 2, so
  `descriptor_signing_input` fail-closed with `signing_input_invalid` —
  both notebooks were broken at execution time, not merely stale to read.
  All nine claims sites now declare revision 2 and both notebooks' full
  cell sequences execute green end to end from their own directory.

### Changed

- The declared Elixir floor drops to `~> 1.19` (tested lines 1.19.x and
  1.20.x), matching `charter_agreement_signer`; anything below 1.19.0 is
  refused by Mix with `Mix.ElixirVersionError` before anything compiles.
  The supported-OTP set is declared as {28, 29} and enforced in-repo:
  `config/config.exs` refuses a foreign OTP major before compilation. The
  set is decided by substrate probe — stable precompiled 1.20.x builds also
  exist for OTP 27, but on OTP 27.3.4.17 with OpenSSL 3.5.5 confirmed
  linked, `:crypto.supports(:public_keys)` exposes none of
  `:mldsa44/65/87`, so the revision-3 corpus fail-closes on 27. The range,
  the set, `.tool-versions`, and the CI matrix lanes move together in one
  commit; docs/adr/supported-otp-set.md records the probes, the proof legs,
  and the floor lane green end to end on Elixir 1.19.5 / OTP 28.5.0.3.
- CI's floor lane mirrors the signer sibling's (Elixir 1.19.5 /
  OTP 28.5.0.3 on ubuntu-26.04). dialyxir moves to 1.4.8 and ex_doc to
  0.40.4; the charter-family `==` pins carry inline exact-identity reasons.
- Dependency currency becomes latest-first and gated
  (docs/adr/dependency-currency-gate.md): `mix currency.check` runs inside
  the quality battery and as its own CI step. The gate fails on any
  resolvable drift, prints every resolver-rejected pin with its requirement
  chain, classifies on the rendered table with whitespace-anchored matches,
  and exits nonzero unverified when the hex.pm lookup renders no table.

### Added

- The Windows clone-and-build bar. `.gitattributes` normalizes line endings
  and marks the byte-exact conformance corpus and test fixtures binary so
  `core.autocrlf` cannot corrupt a Windows checkout; CI gains a
  windows-build lane proving checkout, dependency fetch, test-environment
  compile with warnings-as-errors, format, and the currency gate on the
  official OTP 29 Windows builds, plus an informational runtime
  crypto-capability report. No declared gate depends on a POSIX shell — the
  currency gate is an Elixir script that spawns `mix` through `cmd /c` on
  Windows. The full test suite on Windows is not yet claimed; the gated
  extension is recorded in the supported-toolchain ADR.

## [0.3.1] — 2026-09-15

Docs-and-tooling correction release; no wire-visible or library-code change
(`lib/` is byte-identical to 0.3.0).

### Fixed

- The runtime floor's second axis. The 0.3.0 floor statement named
  OTP ≥ 28.1 but omitted the linked crypto library. ML-DSA (FIPS 204)
  reached OpenSSL in 3.5.0, and OTP's `:crypto` exposes ML-DSA key
  generation and verification only when the runtime's libcrypto is ≥ 3.5.
  The declared floor is therefore OTP ≥ 28.1 with a linked OpenSSL ≥ 3.5.
- CI ran the quality gate on ubuntu-24.04, whose OpenSSL 3.0.x cannot
  generate or verify ML-DSA keys: 7 of 268 tests failed with the OpenSSL
  `Bad key type` error and the corpus's valid ML-DSA verdicts fail-closed as
  `signature_invalid`, while the same tree passed every local gate on a
  runtime linked against OpenSSL 3.6. bob's OTP builds dynamically link the
  distro `libcrypto.so.3` and bundle nothing, so the distro library was the
  only variable. The quality gate now runs on ubuntu-26.04 (OpenSSL 3.5.x)
  with the pinned and floor matrix legs unchanged. On the floor leg
  (OTP 28.1 / crypto 5.7) the two ML-DSA test sign calls now pass the
  documented `mldsa_private` tuple form (`{:expandedkey, binary}`) — crypto
  5.7 rejects the raw binary that later cryptos accept; verification itself
  needs no accommodation (the corpus agrees 100/100 at the floor).
- The release-candidate gate now pins the package CONTENT identity (the
  SHA-256 over the unpacked archive's sorted path+bytes, excluding
  `hex_metadata.config`) instead of the tarball bytes: `mix hex.build`'s
  gzip layer is reproducible within one OS but not across OSes, and the
  generated metadata embeds its file list in filesystem enumeration order —
  so the 0.3.0 byte pin, recorded locally and never before exercised in CI,
  could not match a Linux CI rebuild of identical content. The gate still
  requires byte reproducibility between its two in-run builds and still
  verifies the unpacked boundary and metadata; the content pin hashes only
  git-tracked bytes and passes identically on every platform.
  `record_release_metadata` records the same identity.
- Documentation re-trued to the revision-3 surface (the corpus, guides,
  notebooks, and reference tables had drifted): the certified identities in
  Conformance and Test vectors now carry the live 0.3.0-recertified values;
  the security model's primitives section admits ML-DSA (it still said
  "Ed25519 only"); signature-length and key-history prose states the
  registry-row rule instead of a universal 64-byte/Ed25519 claim;
  `protocol_revision` tables accept 1–3; the error-code reference carries
  the live per-code corpus counts; the corpus quick-start commands
  propagate the CLI exit status through `System.halt/1` and no longer claim
  the repository-only `mix conformance.verify` alias works from an unpacked
  package; install examples carry `~> 0.3.0`; the npm family paragraph notes
  the published companion signer package; the Node verifier floor reads
  ≥ 24.8; the limits table gains the byte-weighted artifact-set ceiling; the
  party-descriptor and receipt signature MUST-clauses in `spec/core.md`
  state the registry row's key algorithm (completing the revision-3 ADR's
  recorded consequence, with the specification digest re-recorded); the
  release-candidate gate now pins the docs' certified-identity tables to
  the live values so a truncated transcription cannot ship; and
  the release runbook describes the content-identity pin.

## [0.3.0] — 2026-09-14

The standards-release: `protocol_revision` 3 (the ML-DSA registry act) plus
the audit hardening batch.

### Protocol (wire-visible, revision-gated)

- ML-DSA admission (RFC 9964; ADR `ml-dsa-admission.md`): the registry gains
  `ML-DSA-44`, `ML-DSA-65`, and `ML-DSA-87` at `protocol_revision` 3, each
  with its exact public-key and signature byte lengths as registry data.
  Verification dispatches per registry row on both implementations; the
  descriptor key grammar admits ML-DSA keys gated on descriptor revision
  (an ML-DSA key in a revision-1/2 descriptor rejects), and mixed-algorithm
  key sets are legal with the Ed25519→ML-DSA bridge exercised by the corpus.
  Producers mint exactly (`Ed25519`, revision 2) or (`ML-DSA-65`,
  revision 3) via the optional `"algorithm"` input member.
- Verdict audit: red→green — (ML-DSA names, revision 3), (EdDSA, revision 3),
  (Ed25519, revision 3), mixed-revision ML-DSA views. Nothing green→red on
  the wire. Unknown revisions still fail closed (revision 4 carries the
  fail-closed corpus probe).

### Resource boundary (not wire-visible; recorded policy)

- `Limits` gains `max_artifact_set_bytes` (default 64 MiB, compiled maximum
  1 GiB); set verification bounds items, bytes, proper-list shape, and
  binaries in one pre-decode traversal — improper lists return typed errors.
- `Chain.verify` passes its own verified facts to the acceptance and
  termination seams, removing the O(A×D) per-artifact re-verification;
  governing computation memoizes ancestry per view.
- The JSON decoder rejects integer lexemes over 21 digits and float lexemes
  over 32 bytes before conversion (linear-time rejection; no accepted value
  changes — oversized spellings could never round-trip).
- Timestamp-valued members carry 1..64 string-byte schema constraints.

### Second verifier parity

- The TypeScript verifier now mirrors the reference implementation: strict
  I-JSON strings (noncharacters, lone surrogates), lexeme-faithful float
  tagging, bounded JWS decode, strict Ed25519 pre-checks, exact timestamps
  (real calendar, the June/December leap-second slot, untruncated
  fractions), the full chain battery (predecessor linkage, one genesis,
  supersession shape, unique acceptance coordinates, role-pair dual
  acceptance, terminations, `effective_until`, ancestry-coverage governing),
  the closed receipt decision/outcome matrix, the ML-DSA registry, and the
  compiled limit maximums.

### Conformance and certification

- Certified corpus regenerated and recertified at 100 cases: the frozen
  ML-DSA population (descriptor positives and per-name negatives, the
  PQ key bridge, the mixed-revision view, ML-DSA acceptance and receipt),
  revision-4 fail-closed, and the (EdDSA, 3) compatibility flip. All four
  certified identities and the archive digest re-recorded; the named
  mutation battery grows to 25.

### Runtime floors

- OTP ≥ 28.1 (the corpus contains ML-DSA cases and report byte-identity
  forbids runtime-conditional verification; `:crypto` ML-DSA landed in
  OTP 28.1). The Node verifier floor rises to 24.8 (ML-DSA in the builtins
  landed across 24.6–24.8). CI now tests the floor toolchain alongside the
  pinned current one.

## [0.2.1] — 2026-08-26

Documentation-only release: the docs now point hosts at the reviewed
companion signer — [`charter_agreement_signer`](https://hex.pm/packages/charter_agreement_signer)
(atomic kid/key snapshot, wrong-key guard, post-sign verify, refusal
surfacing) — from four surfaces (README key-custody, protocol.md
host-obligations, getting-started's new companion section, the charter-tour
notebook's sign-helper cell). Hosts may always hand-roll per the spec;
verifiers never depend on the companion. No protocol, corpus, or identity
changes.

## [0.2.0] — 2026-08-26

`protocol_revision` 2: the RFC 9864 alg-name bundle.

### Protocol (wire-visible, revision-gated)

- The per-artifact binding rule: `alg: "EdDSA"` is accepted at any
  accepted revision; `alg: "Ed25519"` requires `protocol_revision >= 2`;
  unknown revisions fail closed. `(Ed25519, revision 1)` is rejected —
  no honest producer could have minted it.
- New minting is exactly (`Ed25519`, `protocol_revision` 2), enforced by
  construction (the framing-layer binding check runs on the producer's
  provisional decode).
- Cross-revision composition: artifacts from revisions 1 and 2 mix freely
  in one verified view — a revision-2 acceptance anchors a revision-1
  charter. Decoded artifacts carry their actual `protocol_revision`
  (structs no longer pin 1).

### Verifiers

- Both implementations enforce the binding rule at the framing layer; the
  TypeScript reference verifier additionally gained the revision-range
  check it previously lacked, and its acceptance-revision equality was
  replaced by the accepted-set semantics the mixed views require.

### Conformance

- Certified corpus regenerated and recertified (90 cases): the
  revision-2/`Ed25519` population, the revision-2/`EdDSA` compatibility
  case, the `(revision 1, Ed25519)` per-name negative, the revision-3
  fail-closed case, and the mixed-revision acceptance view. Legacy
  fixtures pin revision 1 + `EdDSA` literally, on purpose. All four
  certified identities re-recorded; the requirements matrix grows
  `CAP-REVISION-fail-closed` and `CAP-ALG-registry-binding` with the
  `alg-binding-defeat` source mutation.

## [0.1.0] — 2026-08-26

Everything below is the 0.1.0 candidate content, frozen for the
publication decision; the archive at this commit is the reviewed candidate.

### Conformance

- The certified corpus closes its error-code coverage gap: 28 new cases
  across every surface lift corpus-exercised codes from 19 to 45 of the
  closed 57 (two codes gain cases on a second surface); the remaining twelve are structurally outside case
  certification (corpus loader, producer seams, typed query arguments,
  and the explicit schema-view seam), stated with reasons in the
  error-code reference. The requirements matrix grows to 45 bound
  requirements over 61 applicability cells and 85 certified cases; the
  independent TypeScript verifier implements every newly certified
  failure path, and all four certified identities are re-recorded.

### Documentation

- A complete documentation corpus for integrators and evaluators: ten guides
  (overview, getting started, artifacts, verification semantics, receipts,
  extensions, security model, recipes, conformance, FAQ), two runnable
  Livebook notebooks (charter tour and fork repair, executed against the live
  package), a rewritten landing README, and a contributor guide stating the
  change bar and invariants.
- The package archive now ships the guides and notebooks alongside the
  normative protocol specification; the API reference is grouped by surface
  (artifacts, facts, verification, primitives, extensions, conformance).

### Added

- Foundational byte-contract modules for strict unpadded base64url,
  deterministic tagged JSON, RFC 8785 canonicalization with exact-byte
  verification, domain-separated tagged SHA-256 digests with all-byte
  comparison, and a closed typed error vocabulary.
- Caller-supplied bounded JSON decode limits; a table-driven closed-schema
  engine with fixed seven-stage failure precedence; and a pure conformance
  corpus loader enforcing self-digest, file/hash/count/ID integrity, compiled
  applicability, and non-vacuous expectations.
- A shipped foundational corpus plus a Node 24-or-newer, builtins-only integrity
  harness that independently rejects corrupted corpus bytes and stays outside
  the package archive.
- Strict UTC RFC 3339 timestamps and canonical attached compact-JWS parsing for
  the Party Descriptor boundary, including exact protected-header and Ed25519
  signature checks.
- Closed Party Descriptor decoding and verification with self-signed genesis,
  predecessor-active-key transitions, reverified lineage, linear supersession,
  signed sibling-fork facts, and no winner selection.
- Elixir and Node corpus coverage for valid descriptors, superseded descriptors,
  and signed sibling forks, with exact applicability-floor enforcement.
- Closed unsigned Charter Revision decoding with raw-byte legal-text digests,
  mandatory precedence, bounded temporal and termination declarations, exact
  ABP 0.1.1 deployment identities, and executable cross-language corpus cells.
- Attached Acceptance verification with exact revision/party claim equality,
  reverified descriptor key context, view-relative signer position, and
  same-signer equivocation evidence that never selects a branch.
- Attached Termination Notice verification with exact revision/party binding,
  listed-reason enforcement, pure issue/effective ordering, active descriptor
  key verification, and no clock or governance-effect decision.
- Pure set-level chain verification and caller-time governing computation with
  bilateral acceptance, exact revision ancestry, start-inclusive effective
  windows, retained fork evidence, explicit supersession repair, termination
  closure without fallback, and no digest tie-break.
- One redacted facts-construction boundary that forces the twelve-item
  `not_verified` floor across descriptor, revision, acceptance, termination,
  fork, and chain facts, plus executable Elixir and Node corpus cells for
  chain forks, supersession, and temporal precedence.
- Attached Receipt verification with exact revision-number/digest and ABP
  deployment cross-checks, BAP grant-hash byte identity, total
  decision/outcome states including indeterminate effects, issuing-party
  Ed25519 verification under full chain context, view-relative fork/governance
  facts, redacted ReceiptFacts, and five executable corpus cases.
- Exact development/test-only, runtime-disabled ABP 0.1.1 and BAP 0.1.2 Hex
  dependencies with package checksums and frozen/live byte-identity gates; the
  CAP production application remains OTP-crypto-only.
- Deterministic Party Descriptor, Acceptance, Termination, and Receipt signing
  inputs plus external-signature-only compact assembly. The set-aware seam
  refuses false coordinates and equivocation, requires Acceptance ancestry to
  cover maximum accepted heads while preserving bilateral supersession repair,
  and requires a Termination to name the unique governing revision at its own
  effective time; source and BEAM gates prohibit signing custody.
- Architecture gates that reject implementation-version tokens everywhere
  except the exact Hex package source reference, reject runtime dependency
  drift away from OTP `:crypto`, and keep declared error codes synchronized
  with production emission sites.
- Architecture gates that force every facts record through the shared
  twelve-item omission floor; reject authorization and term-evaluation
  vocabulary; prohibit production filesystem, clock, calendar, shell/OS escape,
  and dynamic-dispatch calls; require public specifications and
  non-authorizing module stances; and census CAP, ABP, and BAP separators and
  protected types for completeness and disjointness.
- A compiled seven-field extension registry with RFC 2606 example-class
  identities, exact critical/optional envelope validation, schema-digest-bound
  critical bodies, fail-closed critical lifecycle handling, and verbatim
  unknown-optional quarantine with names-only facts.
- The indexed-price profile family: closed ISO 4217 revision terms under
  `com.example/pricing-indexed`, optional receipt observation evidence under
  `com.example/pricing-indexed-observation`, authoritative evaluation-semantics
  documentation, and executable valid/invalid/quarantine corpus cells.
- Reserved, schema-free vLEI and eIDAS QEAA attestation profile names. CAP
  interprets no attestation bytes until a normative authority defines and a
  later protocol revision adopts a closed schema.
- A pure conformance runner, canonical identity-bound report, explicit-corpus
  CLI/escript, and compiled requirement map linking every stable public
  requirement to corpus, architecture-gate, and mutation evidence.
- A 57-case obligation-complete corpus whose index binds the compiled extension
  registry and carries both a domain-separated self-digest and a separately
  certified exact-byte SHA-256 pin.
- An independent Node 24-or-newer TypeScript verifier using only built-ins. It
  recomputes every certified signature, artifact and set fact, governing view,
  receipt projection, and foundational codec verdict; its canonical report is
  byte-identical to Elixir over repository and unpacked-package corpora.
- The complete 22-break mutation battery, with baseline-green calibration and
  the corpus-expectation flip last, plus directional second-verifier reds.
- Release metadata, errata policy, conformance/release ADR, NIST CAVP SHA-256
  known-answer checks, exact package allowlist verification, reproducible
  archive comparison, and a mechanical no-publication-authority receipt.
- A separate runnable supplier fork-evidence demo using real signed artifacts. It
  reports same-signer equivocation, a contested governing view, Receipt
  cross-check facts, and a countersigned bilateral supersession repair without
  adjudicating or authorizing.
- Package scaffold: mix project with the complete `mix quality` battery
  (dependency audits, format check, warnings-as-errors compile,
  `credo --strict`, 100% coverage census, conformance, mutations, independent
  verifier agreement, dialyzer, warnings-as-errors docs, and release candidate),
  pinned GitHub CI with a full-history gitleaks secret scan,
  weekly dependabot updates for mix and GitHub Actions, and the
  Apache-2.0 licensing set (LICENSE, NOTICE, SECURITY.md).

### Fixed

- Enumerate hidden corpus entries, reject non-regular paths, and enforce corpus
  byte ceilings before file reads in every filesystem verifier.
- Align the independent verifier's Receipt projection, issuer-key selection,
  JSON structural limits, and compiled extension-registry identity with the
  certified Elixir boundary.
- Require every mutation's exact scratch environment to pass before a failing
  mutated command can receive credit.
- Reject noncanonical Ed25519 points, all eight low-order torsion encodings for
  public keys and signature `R` values, and out-of-range signature scalars
  before runtime verification; this closes the identity-key universal forgery
  accepted by the raw OTP primitive.
- Preserve typed artifact-set verification failures at the signing seam, accept
  JSON float values that the canonicalization and extension boundaries support,
  and make the signing-custody BEAM gate observable under cover compilation.
- Reject I-JSON noncharacters symmetrically during JSON decoding and constructed
  canonicalization, and close alternate error-construction paths that could
  bypass the declared-code and value-free-detail architecture gates.
- Bound complete artifact-set inputs and verify descriptor chains with one
  signature check per artifact instead of repeatedly replaying each predecessor
  lineage.
- Preserve `invalid_limits` across every descriptor and chain entry point, order
  accepted leap-second instants before the following midnight, reject unknown
  critical descriptor extensions until the registry is available, and keep
  long-chain test fixtures on valid timestamps.
- Require wrong-signature and disconnected-chain rejection cells in both corpus
  integrity implementations.
- Return typed revision errors for malformed supersession members and reject
  supersession targets on genesis revisions.
