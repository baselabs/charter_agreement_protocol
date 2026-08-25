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

## Enforcement

Two layers, one landed and one owed:

- **Landed now.** The kimosabe durable-identifier sweep
  (`durable-identifier-check.py`) runs on the staged index and the tracked tree.
  This repository is configured `[durable_identifiers].versioning = "allowed"`,
  which disables only the numbered-version checks so the permitted package-tag
  identity passes; transient `phase`/`task`/`slice`/`sprint`/`step`/`work-order`
  tokens remain blocked regardless of that setting.
- **Owed by the first protocol slice.** The `test/architecture/`
  identifier-naming gate re-narrows the numbered-version allowance to exactly the
  package-tag identity — reding on every conventional token form (leading
  `v<N>`, snake-boundary `_v<N>`, CamelCase hump `V<N>`) and on path segments,
  everywhere except the blessed `mix.exs` source reference. Until that gate
  lands, the numbered-version narrowing is documented here but not yet
  mechanically enforced. The coverage window is currently empty: no protocol
  identifiers exist yet — the package carries only its facade module.

## Consequences

Evolution happens at the revision boundary inside the artifact, where it is
digest-covered and negotiation-gated; the code surface stays version-free and
rename-stable. No module, function, path, config key, test, separator, `typ`,
or internal compatibility branch may derive its name from a release, task, or
implementation sequence. Wire revisions remain digest-covered data. The
architecture gate named above makes any regression loud once it lands, and is a
required deliverable of the first slice that introduces protocol identifiers.
