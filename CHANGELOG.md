# Changelog

All notable public changes to `charter_agreement_protocol` are documented here.

## [Unreleased]

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
- Architecture gates that reject implementation-version tokens everywhere
  except the exact Hex package source reference, reject runtime dependency
  drift away from OTP `:crypto`, and keep declared error codes synchronized
  with production emission sites.
- Package scaffold: mix project with the complete `mix quality` battery
  (dependency audits, format check, warnings-as-errors compile,
  `credo --strict`, 100% coverage census, dialyzer, warnings-as-errors
  docs), pinned GitHub CI with a full-history gitleaks secret scan,
  weekly dependabot updates for mix and GitHub Actions, and the
  Apache-2.0 licensing set (LICENSE, NOTICE, SECURITY.md).

### Fixed

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
