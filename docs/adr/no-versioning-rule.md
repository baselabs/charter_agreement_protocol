# ADR: no version tokens in identifiers

Status: accepted (2026-08-24).

## Context

Charter Agreement Protocol artifacts carry `protocol_revision` as a
digest-covered member of every artifact, and consumers declare an explicit
revision set; compatibility is identity-exact or an error. Identifier-level
version tokens — module names like `V2Decoder`, paths like `priv/v1/`,
function names like `decode_v2`, test file names, config keys — would create a
second, uncoordinated versioning axis: the classic drift surface where two
names each claim to be current and neither is. The approved specification
states this posture as "ABP no-token" (spec, Implementation Decisions).

The Mix/Hex package, by contrast, must carry a semantic version — a released
library without one cannot be depended on. Conflating "no version token in the
protocol surface" with "no version anywhere" is the misreading this ADR closes.

## Decision

No version token appears in any shipped protocol identifier: module segment,
function or macro name, atom, struct key, corpus path, config key, artifact
separator, or `typ` value.

The Hex package's semantic version and its exact `mix.exs` package-tag source
reference — `source_ref: "v#{@version}"` — are the sole permitted
version-bearing durable identities. Path, source kind, and spelling are part of
the allowlist; a version-token lookalike in any other identifier or location is
rejected.

ADR filenames are slug-only, with no numeric sequence prefixes, for the same
reason — document sequence numbers are themselves a versioning axis.

## Boundary exceptions (explicitly approved 2026-09-24)

The release-manifest contract admitted two version-bearing members as
explicitly approved compatibility headers — the sole boundary exceptions
beyond the package semver, each with its own stated scope (owner approval
2026-09-24, recorded with the release-identity act):

1. **The manifest schema version** (`manifest_version`, an integer in
   `priv/release-metadata.json`): the version of the manifest's own SHAPE,
   not of any protocol identity. It bumps only when a member is removed,
   renamed, or retyped; additive members never bump it. Consumers must
   ignore unknown members, so the number moves rarely and always means a
   breaking change in the machine-readable contract.
2. **The verification-semantics identity** (`verification_semantics_version`,
   an integer mirrored from `ReleaseIdentity.verification_semantics/0`): the
   identity of the verdict function, defined and scoped in
   `docs/adr/release-identity.md`. It versions VERDICT BEHAVIOR, which the
   wire's `protocol_revision` deliberately does not (a release may hold the
   wire grammar fixed while verdict semantics move, and vice versa); the two
   axes are coordinated through that ADR, never conflated.

Integer DATA VALUES in the manifest are not version-bearing identifiers —
they are the recorded projections of data-in-code functions, and the
release-candidate gate asserts the projection equals the function. No other
version token is admitted anywhere in the protocol surface.

## Enforcement

Two layers, both landed:

- **Landed now.** The kimosabe durable-identifier sweep
  (`durable-identifier-check.py`) runs on the staged index and the tracked tree.
  This repository is configured `[durable_identifiers].versioning = "allowed"`,
  which disables only the numbered-version checks so the permitted package-tag
  identity passes; transient `phase`/`task`/`slice`/`sprint`/`step`/`work-order`
  tokens remain blocked regardless of that setting.
- **Landed with the first protocol identifiers.** The `test/architecture/`
  identifier-naming gate re-narrows the numbered-version allowance to exactly the
  package-tag identity — failing on every conventional token form (leading
  `v<N>`, snake-boundary `_v<N>`, CamelCase hump `V<N>`) and on path segments,
  everywhere except the blessed `mix.exs` source reference. Its scanner covers
  owned paths plus module, function, macro, atom, struct-key, and test identifiers.
  A scratch mutation that planted a version-bearing module and path made the exact
  gate fail before the live tree was accepted.

## Consequences

Evolution happens at the revision boundary inside the artifact, where it is
digest-covered and negotiation-gated; the code surface stays version-free and
rename-stable. No module, function, path, config key, test, separator, `typ`,
or internal compatibility branch may derive its name from a release, task, or
implementation sequence. Wire revisions remain digest-covered data. The
architecture gate makes any regression loud.
