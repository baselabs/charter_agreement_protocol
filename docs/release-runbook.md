# Release runbook

The maintainers' release process separates qualification from publication.
Covering tests and all commands below that compile or test run on the build box,
never on a workstation, routed there by the maintainers' remote-run tooling. Public
repositories without a build-box checkout are checked in qualification CI at landing.
Building an archive publishes nothing.

The design behind these checks is in the
[release design record](adr/conformance-release-candidate.md).

## 1. Record the identities

Do this whenever the corpus, the extension registry, the specification, the
shipped file list or any shipped file changes. Run the steps in this order:
the last one hashes every shipped file, so it has to see the final bytes.

1. **Corpus.** Change `scripts/generate_conformance_corpus.exs` (and the
   class floor in `lib/charter_agreement_protocol/conformance/corpus.ex` if a
   surface needs a new class), then run

   ```console
   $ mix run scripts/generate_conformance_corpus.exs
   ```

   It rewrites the case files and `priv/conformance/index.json` and prints the
   corpus digest. The generator is the source of truth: `mix
   conformance.verify` regenerates the corpus in a scratch directory and
   fails if a byte differs. To re-index case files without regenerating them,
   run `mix run --no-start scripts/record_conformance_index.exs`. Print the
   index SHA-256 (the SHA-256 of the exact `index.json` bytes) with:

   ```console
   $ mix run --no-start -e 'IO.puts(CharterAgreementProtocol.Conformance.Report.index_identity(File.read!("priv/conformance/index.json")))'
   ```

2. **Index SHA-256 pins.** Put the new index SHA-256 in
   `@certified_index_sha256_base64url` in
   `lib/charter_agreement_protocol/conformance/cli.ex` and in `@index_sha` in
   `test/architecture/package_boundary_test.exs`.

3. **Requirements matrix.** Update the evidence in
   `lib/charter_agreement_protocol/requirement_map.ex` for any new corpus
   cell or mutation, then run `mix run scripts/render_requirements.exs` to
   rewrite `spec/requirements.md`.

4. **Compatibility row.** The live corpus digest is recorded in release
   metadata during development. Preserve released compatibility rows.
   For a new package version, update
   `lib/charter_agreement_protocol/release_identity.ex` so the row for the
   new version carries the live corpus digest as `census_digest`.
   - No verdict changed: keep `@verification_semantics`. If the corpus
     changed, open a new row for the release with an empty `transitions`
     list.
   - A verdict changed: raise `@verification_semantics`, open a new row, and
     list each transition with its class and direction. If a case in a
     frozen corpus changes verdict, add it to the allowlist in
     `scripts/check_historical_differential.exs`.

5. **TypeScript verifier pin.** The cross-implementation checks run the
   TypeScript verifier at the commit in `priv/verifier-source.json`. When the
   corpus or registry moves, move the pin:
   1. In the
      [TypeScript repository](https://github.com/baselabs/charter_agreement_protocol_typescript),
      copy `priv/conformance/` into its `conformance/` directory byte for
      byte, set `CERTIFIED_INDEX_SHA256_BASE64URL` and
      `CERTIFIED_REGISTRY_DIGEST` in `core.ts`, and record the canonical
      Elixir corpus commit. Run the native and browser suites on the
      copied bytes through the maintainers' landing tool.
   2. Here, set `commit` in `priv/verifier-source.json` to that commit. It
      must be on the TypeScript repository's `main` as fetched from GitHub,
      and it must descend from the current pin.
   3. Run `mix verifier.source` to rebuild `_build/verifier-source/`.
   4. Run `mix verifier.agreement`. Its certified-index drift mutation derives
      the original digest from the live pin and must fail against the altered copy.

6. **Documentation identity table.** `scripts/check_release_candidate.exs`
   requires the index SHA-256, corpus digest, registry digest and
   specification digest to appear in each page in its `pins` list, starting
   with the identity table in [docs/guides/conformance.md](guides/conformance.md).
   Update those pages, the case counts in the identity table and in
   `site/index.html`, and the CHANGELOG entry. Any byte change under `spec/` moves the specification
   digest, so copy it after the last specification edit. Step 8 prints it as
   `spec_digest=`; if you take it from there, run step 8 again once the pages
   carry it.

7. **Version.** `@version` in `mix.exs` is the release version, and the
   compatibility row from step 4 lists it.

8. **Release metadata and content pin.** Run

   ```console
   $ mix run --no-start scripts/record_release_metadata.exs
   ```

   It writes `priv/release-metadata.json`, then builds and unpacks the
   archive and writes the content pin to `.release-archive.sha256`. Any later
   edit to a shipped file, a guide included, means running it again.

`priv/release-metadata.json` holds these members, each computed from the
code and the corpus:

| Member | Value |
| --- | --- |
| `format` | `charter-agreement-protocol-release-metadata` |
| `manifest_version` | the metadata schema version (`ReleaseIdentity.manifest_version/0`) |
| `package` | `charter_agreement_protocol` |
| `package_version` | `@version` from `mix.exs` |
| `verification_semantics_version` | `ReleaseIdentity.verification_semantics/0` |
| `compatibility` | every row of `ReleaseIdentity.compatibility/0` |
| `corpus_digest` | the corpus digest from `index.json` |
| `index_sha256_base64url` | the SHA-256 of the exact `index.json` bytes |
| `registry_digest` | the extension registry digest |
| `signature_algorithms` | every row of the signature algorithm registry |
| `signature_registry_digest` | the signature algorithm registry digest |
| `limits` | `default` and `maximum`, from `Limits.default/0` and `Limits.maximums/0` |
| `spec_digest` | the digest of every file under `spec/` |
| `verifier_runtime` | `node>=24.8` |
| `archive_is_publication_authorization` | `false` |

`mix release.candidate` fails if any member differs from the live value, or
if a member is added or removed.

The content pin in `.release-archive.sha256` is the SHA-256 over the unpacked
archive's files, sorted by path, leaving out `hex_metadata.config` (its file
list follows the filesystem's order). The tarball bytes differ between
operating systems, so the pin covers content instead. `mix
release.candidate` builds the archive twice, requires the two builds to match
byte for byte, and requires the content to match the pin.

## 2. Qualify the commit

Run the covering tests on the build box. Landing goes
through the maintainers' landing tool with the full commit, which starts the complete quality
battery on `kci/**` and moves the default branch only after `qualified` succeeds.
Every job listed in [CONTRIBUTING](../CONTRIBUTING.md) must succeed. Qualification
runs only on `kci/**` pushes, including documentation changes; default-branch
pushes, tags, pull requests and dispatches do not start another qualification.

## 3. Records

- `CHANGELOG.md`: the `[Unreleased]` heading becomes the version and release
  date, in the same form as the earlier entries, and the entry describes
  every user-visible change.
- `spec/changelog.md` records every specification change. A change visible
  on the wire names its `protocol_revision` (see `spec/evolution.md`).
- `docs/errata.md` gets an entry if the release corrects a published verdict.

## 4. Land the version commit

Stamp the changelog with the version and release date in the version commit,
and land the exact qualified tree through the maintainers' landing tool. Send one message through
the maintainers' release process with the repository, full commit, version,
what goes out, and the green `qualified` run. This completes release preparation.

`mix release.candidate` builds and inspects the archive and prints its content
pin and archive digest. The docs' `source_ref` is `v<version>`; source links
resolve when the published commit is tagged after registry readback.

## 5. Publication

The release operator owns the `publish` environment and its `HEX_API_KEY`. The release operator obtains release
authorization and dispatches `.github/workflows/publish.yml` on the default branch
with the full qualified SHA as `release_commit`. The first job checks default-branch
history, the successful `qualified` check and the absence of a version tag before
checkout. The workflow takes the registry scripts from its own revision, then builds
the requested commit in a job without the publish environment. The upload job verifies
checksums and runs the workflow revision’s uploader. The build installs the exact runtime and locked dependencies without a dependency cache,
builds the docs, and checks package contents and reproducibility. It builds the
package archive and the docs archive once into `release-assets/`. After the docs
build and before packing, it writes root `release.json` with exactly `package`,
`version` and `commit`; the commit is the validated `release_commit`.

The registry check reads public Hex anonymously. A package name the registry lacks is refused: a first
publication is the owner's decision. A retired version or differing served package
bytes is refused. The package is the release; docs are a rendering of it, and an
ExDoc build is not byte-stable, so docs bytes are never compared: docs the registry
already serves for this version are kept. The keyed step only uploads the two
verified archives, package first, using `mix run --no-mix-exs` from
the runner's temporary directory, with absolute paths to the verified
archives. The uploader re-reads the served state before each POST. It skips a matching package and
docs that the final read reports as served. For a staged package, it first
checks the stage checksum and then confirms the release is still unpublished.
The uploader preserves a matching pending stage with its docs. Hex's client can
resend an in-flight upload if the connection drops before the response. It also
retains the key across a redirect from Hex. A second publisher or approval after
the final read or between attempts is the residual race, controlled by custody of
the publication key. Only the isolated upload job receives that key.

After the owner approves a held upload, dispatch `publish.yml` again with the
same `release_commit`. An earlier matching stage may hold only the package.
Approving that stage publishes the package alone. The next dispatch checks the
served package bytes and uploads the missing docs. If Hex holds the docs for
approval too, approve them and dispatch once more with the same
`release_commit`. The run succeeds only
when read-back serves the matching package and a readable docs archive containing
root `index.html` and `release.json`. The record must name this package and version
and a commit equal to the dispatched commit or an ancestor in the repository's
history. That is the published commit; missing or invalid provenance is refused.
`release.json` is the uploader's record, not an attestation or protection against
a forged claim.

Read-back replaces the built docs archive in `release-assets` with the served
archive. The workflow then records `SHA256SUMS` and exports the `release-assets`
artifact, so its docs are exactly the bytes downloaded and inspected from Hex.
After read-back, the release operator creates and pushes `v<version>` on the published commit
named by the served docs' `release.json`, compares the package archive in
`release-assets` with the registry's bytes, and creates the GitHub release
`v<version>` from those assets. Consumers download the
archives and `SHA256SUMS` from that GitHub release and compare the checksums with
the registry's package checksum. The workflow never creates a release or pushes a
tag. Release preparation does not hold a registry key, publish from a workstation,
dispatch publication or push tags. Never move a published tag or overwrite a
release. Publishing remains outside Mix aliases and project callbacks.

The static hub is a separate publication: the release operator dispatches `pages.yml` on the
default branch to stage and deploy the committed site.

## 6. After publishing

From a clean directory, add the package as a dependency and run:

```console
$ mix run -e 'System.halt(CharterAgreementProtocol.Conformance.Cli.run(["--corpus", "deps/charter_agreement_protocol/priv/conformance"]))'
```

Exit status `0` means the published corpus loads, matches its pinned index
and agrees on every case. `System.halt/1` passes the CLI's status through; a
bare `mix run -e` would drop it. Record the Hex checksum next to the tag.

When the matching `charter_agreement_signer` release is on Hex, run
[Produce and verify with the signer](guides/produce-and-verify.md) and both
notebooks in a clean project with the exact dependency lines they show
(`~> 1.0.0` for both packages). The docs tests execute both tutorials and both
notebooks against this checkout and the matching signer release. During coordinated
preparation, `CAP_DOCS_SIGNER_PATH` may select the real matching signer source; it
never falls back to an older release. CAS also executes its quickstart and third
Livebook. Repeat with a fresh `MIX_INSTALL_DIR` and no source overrides after
publication to check the original Hex install lines.

In the next change, add the new tag and its case count to the frozen-corpus
lists in `scripts/check_historical_differential.exs`, so later releases are
checked against it.

## Released identities never change

Nothing this runbook records is edited after publication: the corpus
identities, the metadata bytes and the content pin describe a released
artifact. A correction is a new release made through this same runbook. The
compatibility table classifies earlier releases; it never rewrites them.
