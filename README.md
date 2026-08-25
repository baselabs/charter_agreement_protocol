# Charter Agreement Protocol

Portable, non-authorizing charter-agreement format and verification protocol.

The package now provides the foundational byte contract used by its artifact
engines: strict unpadded base64url, deterministic JSON decoding, RFC 8785
canonicalization, domain-separated SHA-256 digests, and typed value-free
errors. See [Foundational byte contract](docs/protocol.md).

## Status

Foundational codecs implemented. Artifact schemas and verification engines are
not implemented yet. The package is not published to Hex.

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
