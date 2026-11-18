# Conformance and the release candidate

Status: accepted, August 25, 2026.

## Decision

A release candidate is identified by four values, each with its own job:

- `corpus_digest` is the domain-separated digest inside the canonical corpus index.
  It shows the index is consistent with itself.
- `index_sha256_base64url` is the plain SHA-256 of the exact canonical index bytes.
  The Elixir CLI, the independent Node TypeScript verifier and the packaged release
  metadata all pin this value. It shows the candidate is the reviewed corpus, not just
  some corpus that is consistent with itself.
- `registry_digest` is the digest of the compiled extension registry. The index
  carries it, and it is pinned alongside the index.
- `spec_digest` is the domain-separated digest over a canonical manifest of the
  normative specification files (for each file: its sorted path, byte length and raw
  SHA-256). The release metadata pins it, and the release check recomputes it, so a
  change to any specification byte that is not recorded fails the check.

The corpus loader, the runner and the report are pure and perform no I/O. The CLI is
the only part that reads files. Reports compare each complete projected output or
typed error; agreement on status alone is not enough. The Node verifier uses only
Node built-ins and implements every corpus projection on its own. Reports from the
repository corpus and from the unpacked package must be byte-identical canonical
JSON.

The conformance check regenerates the core corpus in a scratch directory and requires
it to reproduce the recorded bytes. A maintainer who changes the corpus runs the
generation script, which rewrites the case files and the index in
`priv/conformance`. A closed list of supplemental cases (cross-package and profile
cases) stays frozen and is required during regeneration. The full index recorder binds
those cases together with the regenerated core.

The package contents are an explicit allowlist in `mix.exs`. It includes the protocol
code, the corpus, the release metadata and the normative documents. It excludes
tests, scripts, internal project records and the independent verifier. Building or
unpacking the archive checks the candidate's shape. Publication belongs to the
maintainers' release process: infra dispatches `publish.yml` from the qualified
default-branch commit. The keyed step only uploads the two verified archives with
no project loaded. Read-back must serve matching package and docs bytes before
infra tags the commit and creates the GitHub release `v<version>` from the
`release-assets` artifact. Consumers verify the GitHub release's assets.

A name the registry lacks is refused; a first publication is the owner's decision.
For a held release, the owner approves and infra dispatches again on the same
commit. The workflow uploads only what is missing and refuses differing served
bytes or a retired version. It never replaces a package.

## Consequences

Any change to the corpus, the compiled registry, a report or the package contents
invalidates the recorded identities. It requires running conformance again, along
with every named source mutation, verifier agreement, package verification, review,
and hosted CI.

The NIST CAVP SHA-256 known-answer vectors check the runtime primitive. They do not
claim CAVP validation of this package.

The supplier fork demo is a separate repository artifact. It exercises the live
protocol with signed evidence, but it is neither conformance evidence nor package
content.

The TypeScript verifier is no longer kept in this repository. It now lives in its own
repository, and `priv/verifier-source.json` names the commit a release was
checked against.
