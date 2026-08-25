# Charter Agreement Protocol

Portable, non-authorizing charter-agreement format and verification protocol.

The package provides the complete approved core: strict unpadded base64url,
deterministic JSON decoding,
RFC 8785 canonicalization, domain-separated SHA-256 digests, typed value-free
errors, table-driven closed schemas, and a self-digesting conformance corpus.
The artifact engines verify signed Party Descriptors, predecessor-bound key
transitions, linear descriptor history, signed sibling-fork evidence, and
closed unsigned Charter Revisions with exact ABP deployment bindings. Attached
Acceptances prove exact countersignatures and retain same-signer equivocation
evidence without selecting a branch. Termination Notices prove that a pinned
party signed a listed reason and pure effective-time coordinate without
applying a clock or governance-effect policy. Set-level verification composes
both descriptor histories, revisions, acceptances, and notices into redacted
structural facts; caller-time governing queries enforce bilateral assent,
effective windows, supersession, termination closure, and no-tie-break fork
handling.
Receipt verification now binds signed issuing-party evidence to exact revision
coordinates, ABP deployment digests, BAP grant-hash bytes, decision/outcome
states, and view-relative fork/governance facts.
The signing seam emits exact RFC 7515 bytes for descriptors, acceptances,
termination notices, and receipts. It refuses equivocation, stale Acceptance
ancestry, and Termination coordinates that are not uniquely governing at the
notice's effective time. It assembles only externally supplied raw signatures;
CAP never holds or uses a signing key. Verification rejects noncanonical and
low-order Ed25519 inputs before invoking the runtime crypto primitive.
The architecture battery keeps every facts record behind one omission-floor
constructor, rejects authorization and term-evaluation vocabulary, proves the
runtime cannot reach filesystems, clocks, or shell/OS escape routes, requires
public specifications and non-authorizing module stances, and keeps CAP wire
identities disjoint from the exact ABP and BAP dependency pins.
The compiled extension registry now enforces exact critical/optional envelopes,
schema-digest binding, unknown-critical rejection, and verbatim optional
quarantine. Its RFC 2606 example-class indexed-price profile carries closed
revision terms and separate receipt observations while CAP leaves term
evaluation to each host.
The certified 57-case corpus executes every compiled applicability obligation.
Its pure Elixir runner and builtins-only Node TypeScript verifier independently
recompute every certified case's complete projected fact document and emit
byte-identical canonical reports over both repository and unpacked-package
corpora. Twenty-two named
source mutations, three directional verifier reds, exact package-boundary
checks, SHA-256 known-answer tests, and reproducible archive builds close the
release-candidate gate.
The separate runnable Visa fork demo constructs real signed artifacts, exposes
a manufactured same-signer equivocation and contested governing view,
cross-checks an action Receipt, and verifies a countersigned superseding repair.
See [Protocol foundation](docs/protocol.md).

## Status

The approved protocol core, corpus, second verifier, mutation battery, and
release-candidate gates are implemented. The current package remains an
unpublished candidate; building its archive is not authorization to publish it.

## Development

```
mix deps.get
mix quality
```

Run the separate evidence demo with:

```
mix run examples/visa_fork_demo.exs
```

The demo reports signed evidence and structural facts. It never adjudicates a
fork or authorizes an effect, and it is intentionally excluded from the package
archive and conformance corpus.

`mix quality` is the complete gate, run locally and in CI:

- `hex.audit`, `deps.unlock --check-unused`, `deps.audit`
- `format --check-formatted`
- `compile --warnings-as-errors`
- `credo --strict`
- `test --cover --seed 42` (100% coverage census)
- `conformance.verify`
- `conformance.mutations` (22 named source breaks; expectation flip last)
- `verifier.agreement` (Elixir/TypeScript, repository/archive, byte-identical)
- `dialyzer`
- `docs --warnings-as-errors`
- `release.candidate`

## License

Apache-2.0 — see [LICENSE](LICENSE).
