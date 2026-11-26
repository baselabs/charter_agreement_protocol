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
   `test/architecture/release_metadata_test.exs`.

3. **Requirements matrix.** Update the evidence in
   `lib/charter_agreement_protocol/requirement_map.ex` for any new corpus
   cell or mutation, then run `mix run scripts/render_requirements.exs` to
   rewrite `spec/requirements.md`.

4. **Compatibility row.** The live corpus digest is recorded in release
   metadata during development. Qualification compares a released version's
   compatibility row against the corpus at its release tag. For a version
   without a release tag, qualification checks its row against the live corpus.
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

CI builds the package and HTML documentation from locked dependencies and
records the package, version and source commit in the docs archive's
`release.json`. The `qualified` check requires that build to pass. Its CI run
retains the two archives and their manifest for seven days.

With release authorization, the release operator dispatches `publish.yml` on
the default branch using the full qualified SHA as `release_commit`. The
upload job verifies the qualification run and archives, requires the package
to exist, and checks the version tag, stamped changelog and registry state.
It checks for an OTP application version collision across Hex repositories.
The upload job alone uses the `publish` environment and exchanges its
workload identity for a short-lived package-scoped token when Hex needs an
upload.

After approval of a held release or docs upload, dispatch again with the same
`release_commit` and the original CI run ID as `qualification_run`. Read-back
checks both served archives against the same qualification and requires
`release.json` to identify the dispatched commit. It exports those archives
and `SHA256SUMS` in `release-assets`. If the qualification has expired, a
fresh run can proceed only if its archives match any bytes Hex already serves.

After read-back, the release operator compares the package archive in
`release-assets` with Hex's checksum and creates the version tag and GitHub
release on the commit named by the served `release.json`. Consumers verify the
downloaded archives using `SHA256SUMS` and the registry's package checksum.
Never move a published tag or overwrite a release.

The static hub is a separate publication. The release operator dispatches
`pages.yml` on the default branch to stage and deploy the committed site.

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
(`~> 1.0.0` for both published packages). The docs tests execute both
tutorials and both notebooks against the CAP candidate checkout and the
matching signer release. During coordinated preparation, `CAP_DOCS_SIGNER_PATH`
can select the matching signer source. CAS also executes its quickstart and third
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
