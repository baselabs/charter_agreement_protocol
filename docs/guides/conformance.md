# Conformance

How CAP proves — to two independent implementations, under deliberate defects,
and against the exact bytes that would be published — that the protocol you
read about is the protocol you run.

## The certified corpus

The shipped corpus (`priv/conformance`, included in the package archive)
contains 84 certified cases across 14 case files, covering every compiled
applicability surface: foundational codecs (base64url, JSON, canonicalization,
digests), schema validation, party descriptors, descriptor chains, charter
revisions, acceptances and equivocation, terminations, chain verification,
governing revision, and receipts — including fork, quarantine, and profile
cases. Completion is by obligation, not count: every required applicability
cell has executed cases, every not-applicable cell carries a non-empty reason,
and counts must equal observations.

The corpus is self-digesting. Loading (`Conformance.Corpus.load/1`, pure — a
complete `map of relative path to bytes`, no file I/O) requires canonical index
and case bytes, a recomputed domain-separated corpus digest, exact
declared/observed file-set equality with per-file SHA-256 hashes, exact counts,
globally unique case IDs, and **projected outputs for valid cases** — a
verdict-only green is refused, so a runner that says "valid" without producing
the exact expected fact document cannot pass.

## The certified identities

The release-candidate ADR separates these jobs:

- `corpus_digest` — the domain-separated digest *inside* the canonical corpus
  index. Proves the index is self-consistent.
- `index_sha256_base64url` — the raw SHA-256 of the exact canonical index
  bytes. Pinned by the Elixir CLI, the independent TypeScript verifier, and
  the packaged release metadata. Proves the candidate **is the reviewed
  corpus**, not merely a newly self-consistent one.

For the current candidate:

| Identity | Value |
|---|---|
| Corpus digest | `sha-256:hZPH5yw_6vWWTj-NuSjlDItK-e8oiGKvjpCXvb24j-0` |
| Index SHA-256 (base64url) | `SiGK6zgrI9Rv5BvBPgj3-EexxJ1udz8-XtDDjeOiRv0` |
| Compiled registry digest | `sha-256:u754joyHGcLCTm1LYV2s6eHauUUdDfJDwwyhbAbxvzc` |
| Specification digest | `sha-256:dAKqvu-7sO5tMxjrN8qeisHHanxTWKOLhZyBPIr-FaE` |
| Certified cases | 84 |

## The requirements matrix

Every public requirement carries a stable `CAP-<SURFACE>-<kebab-tag>`
identifier (see the [errata policy](../errata.md)) and compiled evidence
routing in `CharterAgreementProtocol.RequirementMap`: corpus cells,
architecture gates, and — for the closed mutation battery — named red-capable
source mutations. `spec/requirements.md` is generated from that map
(`mix run scripts/render_requirements.exs`). `mix conformance.verify` rejects
a stale render and enforces bidirectional coverage: every requirement carries
evidence, and every corpus cell and named mutation is bound to at least one
requirement. The generated matrix carries the exact live counts; the closed
mutation battery is bound one-to-one to the requirements that name it.

## The CLI

```console
$ charter_agreement_protocol --corpus DIRECTORY
```

Exit `0` — every certified case recomputed and agreed; the canonical JSON
report on stdout carries per-case actual and expected documents, agreement
counts, and all three report identities. Exit `1` — load or verification
failure. The fourth certified identity — the specification digest — is
pinned in the release metadata and enforced by the release-candidate gate.
Exit `2` — usage. The CLI is the sole filesystem adapter (≤ 64 files,
≤ 32 MiB) and refuses any corpus whose raw index identity is not the certified
pin — including a freshly regenerated, internally consistent one.

## The gate battery

`mix quality` runs everything below plus audits, formatting, warnings-as-errors
compile, strict credo, the full test suite with its coverage threshold,
dialyzer, and docs:

- `mix conformance.verify` — runs the certified corpus and **regenerates the
  core cases in a scratch directory**, requiring byte identity with the
  certified corpus. A closed set of supplemental cross-package and profile
  cases (frozen at their owning boundaries — the exact ABP 0.1.1 deployment
  and BAP 0.1.2 grant vectors) stays frozen and required. The same gate
  proves the requirements matrix is fresh and bidirectionally covering, and
  enforces the wire grammar schemas.

## Wire grammar schemas

`spec/schemas/` is the single normative machine grammar for every externally
consumed wire format: the five artifact claim sets, the extension envelope,
the compact-JWS protected header, the tagged-digest and timestamp grammar,
and the corpus index and canonical report documents. Every schema is JSON
Schema 2020-12 restricted to the closed 16-keyword subset validated by the
pinned `AgentBlueprintProtocol.Schema` — no other dialect file exists and no
new dependency is introduced. Character-set shape, byte-exact bounds,
cross-field rules, and conditional member presence stay codec-enforced and
normative in the spec text; the schema layer expresses member closure,
types, enumerations, ranges, and cardinalities (see the schema README).

The gate proves both directions: every valid corpus artifact (claim sets,
protected headers, revision texts, the shipped index, and the live canonical
report) validates against its schema, and each shipped constraint carries a
constructed single-defect negative observed to fail. Two completeness floors
keep the set honest against drift — each artifact schema must declare
exactly the member and required sets of the codec definition it serves, and
every properties-bearing schema object must be closed. The extended
`conformance.verify` completes in ~1.7s against a 3s budget.
- `mix conformance.mutations` — creates isolated scratch copies and proves all
  **22 named source defects go red**: JCS number defeat, padding acceptance,
  separator collapse, unknown-member acceptance, chain signature skip, digest
  equality skip, Ed25519 defeat, typ confusion, reason-code uncheck, precedence
  collapse, facts-union suppression, fork-topology suppression, contested
  tie-resolution, equivocation guard removal, receipt conflict silencing, and
  more — with `corpus-expectation-flip` running last. Each run first proves
  the unmodified baseline green.
- `mix verifier.agreement` — the builtins-only Node 24+ TypeScript verifier
  independently recomputes every certified case (including Ed25519 evidence,
  forks, supersession, governing views, receipt fact JSON) and must produce
  reports **byte-identical** to the Elixir runner over both the repository
  corpus and the corpus unpacked from the Hex archive. Directional seeded
  reds (verdict inversion, report-format drift, certified-index drift) prove
  the comparison can fail.
- `mix release.candidate` — verifies canonical release metadata, all three
  certified identity pins inside the CLI and the TypeScript verifier core,
  development/test-only dependency direction, regular-file package inputs,
  **two independently built byte-identical archives**, and exact unpacked
  archive membership.

## Cryptographic known answers

The SHA-256 gate uses current NIST CAVP byte-oriented vectors (empty input,
`d3`, `b4190e`) under FIPS 180-4. These verify the runtime primitive against
published answers; they do not claim CAP has undergone CAVP validation.

## Changing the corpus deliberately

`scripts/record_conformance_index.exs` is the full-corpus index recorder after
a deliberate case change. Any corpus, registry, report, or package-boundary
change invalidates the recorded identities and requires re-running
conformance, all named mutations, verifier agreement, package verification,
review, and hosted CI. Verdict-changing corrections to a published protocol
follow the [errata policy](../errata.md).
