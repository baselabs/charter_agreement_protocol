# No version tokens in identifiers

Status: accepted, August 24, 2026.

## Context

Every Charter Agreement Protocol artifact carries `protocol_revision` as a
digest-covered member, and consumers declare an explicit set of revisions they accept.
Compatibility is exact, or it is an error. Version tokens in identifiers (module names
like `V2Decoder`, paths like `priv/v1/`, function names like `decode_v2`, test file
names, config keys) would create a second versioning axis that nothing coordinates.
That is the classic drift problem: two names each claim to be current, and neither
is. The specification takes the same position: `spec/evolution.md` makes
`protocol_revision` the sole version identity of the wire, with no parallel module
families, path families or media types for new revisions.

The Mix and Hex package, on the other hand, must carry a semantic version. A released
library without one cannot be depended on. Reading "no version token in the protocol
surface" as "no version anywhere" is the mistake this record rules out.

## Decision

No version token appears in any shipped protocol identifier: module segment, function
or macro name, atom, struct key, corpus path, config key, artifact separator, or `typ`
value.

The Hex package's semantic version and its exact `mix.exs` source reference for the
package tag, `source_ref: "v#{@version}"`, are the only version-bearing durable
identities allowed. Path, source kind and spelling are all part of the allowlist. A
version-like token in any other identifier or location is rejected.

ADR file names are slugs with no numeric sequence prefix, for the same reason:
document sequence numbers are a versioning axis too.

## Boundary exceptions (added September 24, 2026)

The release-manifest contract admitted two version-bearing members as compatibility
headers. They are the only exceptions besides the package version, and each has its
own stated scope. Both were added with the release-identity change:

1. **The manifest schema version** (`manifest_version`, an integer in
   `priv/release-metadata.json`). It versions the manifest's own shape, not any
   protocol identity. It changes only when a member is removed, renamed or retyped;
   added members never change it. Consumers must ignore unknown members, so the number
   changes rarely and always means a breaking change in the machine-readable contract.
2. **The verification-semantics identity** (`verification_semantics_version`, an
   integer mirrored from `ReleaseIdentity.verification_semantics/0`). It identifies the
   verdict function, as defined in the [release identity record](release-identity.md).
   It versions verdict behavior, which the wire's `protocol_revision` deliberately
   does not: a release may hold the wire grammar fixed while verdicts change, and the
   other way around. The two axes are coordinated through that record and never
   conflated.

Integer data values in the manifest are not version-bearing identifiers. They are the
recorded output of functions defined in code, and the release check asserts that each
recorded value equals the function's result. No other version token is admitted
anywhere in the protocol surface.

## Enforcement

The identifier-naming test in `test/architecture/` allows numbered versions only for
the package tag identity. It fails on every usual token form (a leading `v<N>`, a
snake-case `_v<N>`, a CamelCase `V<N>`) and on path segments, everywhere except the
`mix.exs` source reference. Its scanner covers owned paths plus module, function,
macro, atom, struct-key and test identifiers, so adding a version-bearing module or
path makes it fail.

## Consequences

The protocol evolves at the revision boundary inside the artifact, where the change is
digest-covered and both parties have to accept it. The code surface stays free of
versions and stable under renames. No module, function, path, config key, test,
separator, `typ` or internal compatibility branch may take its name from a release,
a task or an implementation sequence. Wire revisions stay digest-covered data. The
architecture test makes any regression visible at once.
