# Changelog

All notable public changes to `charter_agreement_protocol` are documented here.

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
