# Charter Agreement Protocol

Portable, non-authorizing charter-agreement format and verification protocol.

The package now provides the bounded byte and validation foundation used by its
artifact engines: strict unpadded base64url, deterministic JSON decoding,
RFC 8785 canonicalization, domain-separated SHA-256 digests, typed value-free
errors, table-driven closed schemas, and a self-digesting conformance corpus.
The artifact engines verify signed Party Descriptors, predecessor-bound key
transitions, linear descriptor history, signed sibling-fork evidence, and
closed unsigned Charter Revisions with exact ABP deployment bindings.
See [Protocol foundation](docs/protocol.md).

## Status

Foundational codecs, bounded decode limits, the schema engine, corpus loader,
independent Node integrity harness, Party Descriptor verification, and Charter
Revision decoding are implemented. Acceptance, termination, governing-chain,
and receipt engines remain under construction. The package is not published to
Hex.

## Development

```
mix deps.get
mix quality
```

`mix quality` is the complete gate, run locally and in CI:

- `hex.audit`, `deps.unlock --check-unused`, `deps.audit`
- `format --check-formatted`
- `compile --warnings-as-errors`
- `credo --strict`
- `test --cover --seed 42` (100% coverage census)
- `dialyzer`
- `docs --warnings-as-errors`

## License

Apache-2.0 — see [LICENSE](LICENSE).
