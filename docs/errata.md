# Errata policy

CAP never authorizes.

This file records verdict-changing corrections to the published protocol. It
is empty for the current release candidate. A future correction must name the
affected stable `CAP-<SURFACE>-<kebab-tag>` requirements, update their corpus,
gate, and mutation evidence, re-certify the corpus index, and preserve the
no-versioning rule: semantic wire changes advance `protocol_revision`; they do
not introduce parallel module, path, or media-type families.

An archive build is verification evidence only. It is not authorization to
publish a package.

## Released-identity immutability

Released identities — digests, certified corpora, release manifests — are
never mutated in place. A correction to any released identity is a new
release; the retroactive semantics mapping is a documented classification
of already-released artifacts, never a rewrite of a released manifest
(docs/adr/release-identity.md).
