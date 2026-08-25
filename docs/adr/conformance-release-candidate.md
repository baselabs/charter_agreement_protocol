# Conformance and release-candidate boundary

Status: accepted — 2026-08-25

CAP never authorizes.

## Decision

The release candidate is certified by two identities with distinct jobs:

- `corpus_digest` is the domain-separated digest inside the canonical corpus
  index. It proves the index is self-consistent.
- `index_sha256_base64url` is the raw SHA-256 of the exact canonical index
  bytes. The Elixir CLI, independent Node TypeScript verifier, and packaged
  release metadata pin that value. It proves the candidate is the reviewed
  corpus, not merely a newly self-consistent corpus.

The pure corpus loader, runner, and report perform no I/O. The CLI is the sole
filesystem adapter. Reports compare every complete projected output or typed
error; status-only agreement is insufficient. The Node verifier uses only
Node built-ins and independently implements every certified corpus projection.
Repository and unpacked-package reports must be byte-identical canonical JSON.

Core corpus regeneration runs only in a scratch directory and must reproduce
the certified bytes. A closed list of supplemental cross-package and profile
cases remains frozen and is required during regeneration; the full index
recorder binds those cases with the regenerated core.

The package boundary is an explicit `mix.exs` allowlist. It includes protocol
code, the certified corpus, release metadata, and normative documents. It
excludes tests, scripts, lifecycle records, and the independent verifier.
Building or unpacking the archive proves candidate shape; only a separately
authorized `mix hex.publish` action can publish it.

## Consequences

Any corpus, compiled registry, report, or package-boundary change invalidates
the recorded identities and must re-run conformance, all named source
mutations, verifier agreement, package verification, review, and hosted CI.
NIST CAVP SHA-256 known-answer vectors check the runtime primitive, but do not
claim CAVP validation of this package.

The Visa fork demo is a separate repository artifact. It exercises the live
protocol with signed evidence but is neither conformance evidence nor package
content.
