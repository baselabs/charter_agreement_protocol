# Changelog

All notable public changes to `charter_agreement_protocol` are documented here.

## [Unreleased]

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
- A separate runnable Visa fork-evidence demo using real signed artifacts. It
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
