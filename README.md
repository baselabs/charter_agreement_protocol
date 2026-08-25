# Charter Agreement Protocol

Portable, non-authorizing charter-agreement format and verification protocol.

The package now provides the bounded byte and validation foundation used by its
artifact engines: strict unpadded base64url, deterministic JSON decoding,
RFC 8785 canonicalization, domain-separated SHA-256 digests, typed value-free
errors, table-driven closed schemas, and a self-digesting conformance corpus.
See [Protocol foundation](docs/protocol.md).

## Status

Foundational codecs, bounded decode limits, the schema engine, corpus loader,
foundational corpus, and independent Node integrity harness are implemented.
Artifact-specific schemas and verification engines are not implemented yet.
The package is not published to Hex.

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
