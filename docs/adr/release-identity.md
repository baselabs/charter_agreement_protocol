# Release identity: the manifest contract, the semantics identity, and the capability profile

Date: September 24, 2026

## Status

Accepted. Governs the release-identity change in 0.4.0. The same release also fixed
the descriptor timestamp floor. Since 0.5.0, the capability profile also applies to
the context a standalone call verifies again.

## Context

A consumer that verifies with the installed package, stores the release identity it
verified under, and requires exact equality on replay hits a wall: any upgrade
conflicts with every stored binding, because the stored tuple includes the package
version and corpus digests.

At the same time, 0.3.0 had changed verdicts for existing valid inputs (seven
timestamp members gained a floor of 1 to 64 bytes, and the default byte budget
rejected oversized views). And runtimes that cannot verify ML-DSA (Ubuntu 24.04 with
OpenSSL 3.0.x) rejected those artifacts as `signature_invalid`, which cannot be told
apart from forgery.

Consumers needed four things: a versioned, machine-readable identity contract, an
accurate account of what the runtime can verify, the protocol revision in the
verification output, and a stated rule that released identities never change.

On Ubuntu 24.04 (OpenSSL 3.0.13), OTP 28.5 and 29.1 both report
`:crypto.supports(:public_keys)` with no `:mldsa*` atom. So the declaration reflects
both the OTP and the linked-OpenSSL requirement, and the diagnostic is available on
exactly the kind of runtime that needs it.

## Decision

### The manifest contract

`priv/release-metadata.json` is a versioned public contract. `manifest_version`
versions its shape. Changes are additive only, consumers MUST ignore unknown members,
and removing, renaming or retyping a member changes the version in a breaking
release. Every member that is data defined in code is the recorded result of a pure
function: `Limits.default/0` and `Limits.maximums/0`, `Algorithm.registry/0` and
`Algorithm.registry_digest/0` (the signature registry's own identity; the extension
registry's digest never identified signature algorithms),
`ReleaseIdentity.manifest_version/0`, `verification_semantics/0` and
`compatibility/0`. The release check asserts that the manifest bytes equal the live
values, member by member. The archive content pin proves the bytes are the reviewed
bytes. The comparison with the live functions proves they are true.

### The verification-semantics identity

`verification_semantics_version` identifies the verdict function of the verification
core over artifact-set inputs, across all valid `Limits`, on a runtime that can verify
every registry algorithm, with no capability profile narrowing it. It changes, against
the release just before, when any of these happens:

- some input's verdict changes in either direction (newly accepted inputs count: a
  consumer whose evidence records "did not verify" is affected when that becomes
  "verified");
- the error code for some input changes;
- any `Limits.default/0` value changes, because defaults are what every consumer that
  sets no limits gets;
- some input that returned a verdict now raises.

Error subjects and details, runtime capability outcomes (a diagnostic local to one
implementation), crashes that become typed errors, and facts-record fields are outside
the identity. This is the strict definition on purpose. The cost is that every
registry change moves the value. The benefit is that a release that changes only
documentation keeps it constant while the corpus digest moves, which is the reason to
keep the two apart.

The mapping back to earlier releases is published as data
(`ReleaseIdentity.verification_semantics_history/0`) and checked on every release by
the differential check. At the time of this decision it read:

| Semantics | Packages | Changes since the previous value |
|---|---|---|
| 1 | 0.1.0 | none |
| 2 | 0.2.0, 0.2.1 | revision-2 inputs newly accepted |
| 3 | 0.3.0 to 0.3.2 | ML-DSA inputs newly accepted; seven timestamp floors (now rejected); the default byte budget (now rejected at defaults); improper lists (crash to typed error) |
| 4 | 0.4.0 | the descriptor timestamp floor (now rejected), the last timestamp member without one |

Later releases add rows to that function. Read it, not this table, for the current
mapping.

### How the identity is checked, and what the check claims

A check that runs on every release runs every frozen corpus from earlier releases
(v0.1.0 through v0.3.2 at the time) under the current package, through the pure
runner. Verdicts must agree, except for an enumerated allowlist of changes keyed by
(tag, case), and each corpus family must tie to its frozen index's own corpus digest.
The published claim says only what the check shows: finite evidence over named inputs,
never a proof that all inputs behave the same.

The corpus loader gains an explicit historical mode. It keeps every integrity check
on the corpus itself (self-digest, per-file hashes, file set, count reconciliation)
and relaxes two checks: the compiled floor on which surfaces must be covered, because
a frozen index from before a surface existed cannot cover it, and equality with the
compiled extension-registry digest, because a frozen index records the registry of
its own release.

### Capability reporting

`capabilities()` returns one verdict per registry row. Each comes from verifying a
pinned known-answer vector, run only when the runtime declares the matching
public-key algorithm. It tests the operation itself, not the runtime's claim about
itself. The linked crypto library is reported for information only. The TypeScript
verifier answers the same way, with the same pinned bytes.

`:algorithm_unsupported_on_substrate` is a diagnostic local to the implementation, not
a protocol verdict. It is outside the conformance verdicts and outside the report
bytes that two verifiers must agree on. It means the signature could not be checked:
the checks that run before the signature check passed, and whether the signature is
valid is unknown. A malformed or wrong-length signature still fails with
`signature_invalid` first, but a forged signature of the right length gets the
diagnostic, so it is never a pass. It passes through every aggregator, including the
receipt path's rule that exactly one candidate key verifies. Its evidence on a real
runtime is a CI job on Ubuntu 24.04 with OpenSSL 3.0.13, which checks that ML-DSA
fails with this diagnostic, while the other CI jobs check that it verifies.

### The capability profile

`Capability.Profile` is pure data the caller supplies, validated like `Limits`, that
fails closed with `:invalid_profile` before verification starts. It has two axes, the
accepted envelope `alg` names and the accepted `protocol_revision` range, applied per
artifact. It is passed through every verify path, never applied as a first pass,
because a first pass would change which error wins when several apply. Since 0.5.0
that includes the context a standalone acceptance, termination or receipt call
verifies again: the supplied revision (revision axis only, since it is unsigned), then
the descriptor history or chain view, then the artifact itself. An artifact outside
the profile fails with `:algorithm_outside_profile` or `:revision_outside_profile`
before its own signature is checked, on every runtime alike.

The profile deliberately does not constrain declared key material. A descriptor that
declares ML-DSA keys but is signed with Ed25519 is inside the profile for an
Ed25519-only deployment. A deployment that must exclude lineages with ML-DSA keys
narrows the revision axis instead, since ML-DSA key material is legal only from
revision 3. Verifying with the full profile is exactly the same as verifying without
one.

### Immutability

Released identities (digests, corpora, manifests) are never changed in place.
Corrections are new releases. The mapping back to earlier releases above is a
documented classification of artifacts already released, never a rewrite of a
released manifest. Packages before 0.4.0 carry none of these members and never will.

## Consequences

- Consumers bind to the semantics identity, the limits they use, the
  signature-registry digest and each artifact's `protocol_revision`, instead of corpus
  digests and package numbers. `protocol_revision` is exposed on each artifact's
  facts record (descriptor, revision, acceptance, termination and receipt facts), and
  the records for signed artifacts also carry the envelope `alg`. Unsigned revision
  facts have no envelope, so their `alg` is `nil` by design. The
  [upgrade guidance](../guides/upgrading-verification-identity.md) issued with this
  release says plainly that nothing on the protocol side can
  preserve an existing exact-equality replay: the stored identity tuple has to change
  what it holds, not just its labels.
- The cost per release: every release runs the differential check again and records
  the corpus digest again, and every registry change moves the semantics value.
- The declared floors do not change: OTP 28 or 29 with OpenSSL 3.5 or later linked,
  for the full corpus. The CI job on a runtime without ML-DSA is evidence, not a
  change of floor. A runtime without ML-DSA is a supported deployment that fails
  clearly, through the profile and the diagnostic.

## Rejected alternatives

- Tying the semantics identity to limits the caller pins, with newly accepted inputs
  excluded. A consumer using default limits that records non-verifications could see
  its evidence flip while the identity stayed constant. That would be reassurance,
  not an identity.
- A compatibility matrix written as prose. It drifts (the 0.3.1 release had to repair
  one), and checking the value in code is what makes the member acceptable at all
  under the no-versioning rule.
- Deriving the capability verdict from `:crypto.supports` alone. Running the operation
  is the reliable test. The declaration only keeps the probe safe on runtimes that
  lack the operation.
- A profile axis over declared key material. It would give one condition two error
  codes, and the key grammar's own revision rule already covers it.

## Revisit triggers

- A composite-signature RFC or a JOSE registry change uses the same algorithm slot.
  The registry change moves the semantics identity, and the compatibility table
  records the changes.
- A consumer needs a different identity axis. Extend the manifest additively; the
  schema version does not change.
