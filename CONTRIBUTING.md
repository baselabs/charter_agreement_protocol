# Contributing

CAP is a verification protocol: nearly every contribution is a contract
change, and the bar reflects that. This document tells you what that bar is
and how to meet it.

## Development

```console
$ mix deps.get
$ mix quality
```

`mix quality` is the complete gate battery, identical locally and in CI:
dependency audits, format check, warnings-as-errors compile, strict credo,
the full test suite with its coverage threshold, the certified conformance
corpus (with regeneration byte-identity), all 22 named source mutations,
Elixir/TypeScript verifier agreement over repository and unpacked-package
corpora, dialyzer, docs with warnings-as-errors, and the release-candidate
gate (reproducible archive, exact package boundary). See
[Conformance](docs/guides/conformance.md).

The independent Node verifier needs Node 24+.

## The bar for a change

- **Red before green.** Every behavior change and every new gate arrives with
  a test that was seen failing for exactly the defect it guards. A green gate
  without a red-capable proof is incomplete.
- **Mutation receipts.** New verification behavior extends the named mutation
  battery — prove the exact protected defect goes red in an isolated scratch
  copy. Never tamper the live tree to demo a failure.
- **Corpus changes are certification events.** A deliberate corpus or registry
  change re-runs `scripts/record_conformance_index.exs` and invalidates the
  three certified identities (corpus digest, raw index SHA-256, registry
  digest) in `priv/release-metadata.json`, the Elixir CLI pin, and the
  TypeScript verifier pin. Conformance, mutations, verifier agreement,
  release-candidate, review, and CI must all re-run.
- **Docs land with the change.** New public behavior ships with its guide
  section, changelog entry, and API documentation in the same landing. Doc
  claims are held to the same standard as code: every technical statement
  traces to the implementation, the certified corpus, or a cited primary
  source — no aspiration-as-fact.
- **Notebooks must run.** If you change an API a notebook touches, re-run the
  notebook's code sequence top to bottom before landing.

## Invariants (the short list)

- CAP never authorizes. No authorization-decision or term-evaluation
  vocabulary enters production source; every explicit module states its
  non-authorizing boundary.
- Production runtime uses only OTP `:crypto` — no filesystem, clock, network,
  environment, process dictionary, or application callbacks in verification
  paths. Callers supply time, limits, trust, and keys.
- Every public function, macro, and delegate carries a specification.
- Every facts record is built through the single omission-floor constructor;
  the closed twelve-item `not_verified` floor cannot shrink.
- All Mix dependencies stay development/test-only with `runtime: false`. No
  `path:` or `git:` dependencies in the committed manifest.
- No version tokens in durable identifiers — no `V2Decoder`, `priv/v1/`,
  `decode_v2`, or phase/task tokens in any path, module, function, atom,
  struct key, or test name. The Hex package semver and its exact `source_ref`
  tag are the only version-bearing identities (see
  [the versioning ADR](docs/adr/no-versioning-rule.md)).
- Errors stay value-free: closed code vocabulary, protocol-owned subjects, no
  rejected input in any error.

## Package boundary

The shipped archive is an explicit allowlist in `mix.exs` (code, certified
corpus, release metadata, and named public documents). Tests, scripts, the
independent verifier, and environment files never ship. If you add a public
document, add it to the allowlist and to the docs extras; the
release-candidate gate verifies exact unpacked membership either way.

## Commits

Stay on `main`; stage explicit pathspecs (never `git add .`/`-A`); write the
what and the why in the commit body. CI must be green at the exact pushed SHA.

## Reporting a security issue

See [SECURITY.md](SECURITY.md) — do not open a public issue for security
content.
