# Errata

This page records corrections that change a verdict a published release
returned in error.

Other changes in verdicts between releases, such as a newly admitted
algorithm, are not errata. Each release's compatibility row lists every
verdict change, with its direction (for example green to red), and
`ReleaseIdentity.compatibility/0` returns the same table. The
[upgrade guide](guides/upgrading-verification-identity.md) explains how to
read it.

## 0.5.0

- **One party in both roles.** Releases 0.1.0 through 0.4.1 verified a
  charter in which one party held both roles, when an unrelated second key
  history was present in the view. 0.5.0 rejects it: a revision that names one
  descriptor for both roles fails with `:revision_invalid`, and a chain view
  whose revision parties resolve to one key history, or that holds a key
  history no revision names, fails with `:chain_invalid`. Requirement:
  `CAP-CHAIN-distinct-parties`. Cases: `charter-revision-shared-descriptor`
  and `chain-one-party-both-roles`. The 0.5.0
  compatibility row lists it as a green-to-red transition, and the
  verification semantics version moves from 4 to 5. No `protocol_revision`
  changes, because no wire grammar changed.
- **Profile on supplied context.** Releases 0.4.0 and 0.4.1 applied a
  narrowed capability profile passed to `verify_acceptance/5`,
  `verify_termination/5` or `verify_receipt/4` only partly: not to the
  revision, descriptor history or chain view supplied with the artifact,
  and not at all to a receipt checked against a bare revision. 0.5.0
  applies it to all of them, and reports a profile rejection under its own
  code where `verify_descriptor/4` and a receipt with an unknown `kid`
  reported another. Requirement:
  `CAP-PROFILE-context-admission`. The verification semantics version is
  defined without a profile, so this correction does not move it; the
  `profile_*` cases on `party_descriptor.verify`, `acceptance.verify`,
  `termination.verify` and `receipt.verify` test it.

The [changelog](../CHANGELOG.md) says how to check results you stored under
an earlier release.

## How a correction is made

A correction is a new release. It:

- names the affected requirements by their `CAP-<SURFACE>-<tag>` identifiers
  (see the [requirements matrix](../spec/requirements.md));
- adds or changes conformance cases so the corrected verdict is tested, and
  re-records the corpus identities;
- advances `protocol_revision` when the change is visible on the wire,
  instead of adding a parallel module, path or media type;
- adds an entry to this page.

## Released identities never change

Digests, conformance corpora and release metadata from a published release
are never edited in place. A correction ships in a new release with its own
identities. The compatibility table describes releases that already shipped;
it does not rewrite their metadata. The
[release identity design record](adr/release-identity.md) has the details.
