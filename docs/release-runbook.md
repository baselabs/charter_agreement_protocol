# Release runbook

CAP never authorizes. Building an archive is verification evidence, never
authority to publish.

The release-candidate boundary is governed by
[docs/adr/conformance-release-candidate.md](adr/conformance-release-candidate.md);
this runbook is the operator sequence for cutting a package release.

## 1. Gates green

```
mix quality
```

The complete gate must pass on the pinned toolchain: audits, formatting,
warnings-as-errors compile, strict credo, the full suite at its coverage
threshold, certified-conformance verification and regeneration identity, all
named source mutations, Elixir/TypeScript verifier agreement over the
repository and unpacked-package corpora, dialyzer, docs, and the
release-candidate archive checks.

## 2. Record identities

After any corpus, registry, spec, or package-boundary byte change:

```
mix run --no-start scripts/record_conformance_index.exs   # full-corpus index
mix run --no-start scripts/render_requirements.exs        # requirements matrix
mix run --no-start scripts/record_release_metadata.exs    # four identities + archive pin
```

`priv/release-metadata.json` carries `corpus_digest`,
`index_sha256_base64url`, `registry_digest`, `spec_digest`,
`verifier_runtime`, and `archive_sha256_base64url` — the digest of the exact
archive bytes produced by `mix hex.build` on this tree. The release-candidate
gate rebuilds the archive twice, requires the builds to be identical, and
requires both to equal the recorded pin.

## 3. Version and records

- `@version` in `mix.exs` matches the CHANGELOG's unreleased entry.
- `CHANGELOG.md` describes every public change.
- `spec/changelog.md` records spec-set changes; semantic wire changes name
  their `protocol_revision` (see `spec/evolution.md` and the ADRs).

## 4. Tag and build

```
git tag vX.Y.Z
mix hex.build
```

Verify the built archive's SHA-256 equals `archive_sha256_base64url` in
`priv/release-metadata.json` (base64url, unpadded) before anything else.

## 5. Publish (separate authority)

`mix hex.publish` is never aliased or automated. Publishing requires explicit
operator authority for THIS release; the approval covers the named version
and archive digest, nothing more.

## 6. Post-publish verification

From a clean directory, add the package as a dependency, then:

```
mix run -e 'CharterAgreementProtocol.Conformance.Cli.run(["--corpus", "deps/charter_agreement_protocol/priv/conformance"])'
```

A returned status of `0` proves the published corpus recomputes and agrees
with the certified identity. Record the published hex checksum beside the
release tag and close the CHANGELOG entry.
