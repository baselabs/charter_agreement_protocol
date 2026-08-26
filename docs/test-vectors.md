# Test vectors

CAP never authorizes.

This manifest is what a third implementation needs to prove byte-agreement
with the certified Charter Agreement Protocol corpus: the four certified
identities, the corpus layout, the runner contract, and the byte-agreement
procedure the repository's own independent verifier already follows. The
TypeScript verifier under `verifier/` (Node built-ins only, Node 24+) is the
reference second implementation; a third implementation repeats its
procedure.

## The four certified identities

All four live in `priv/release-metadata.json` (canonical JSON) and are
enforced by the release-candidate gate. Every value below is the live
recorded value for the current candidate:

| Identity | Value | Job |
|---|---|---|
| Corpus digest | `sha-256:ORUavQBNHFZG8XEAsunlHaHXDMMaNMW2ggImIotd-n4` | Domain-separated digest inside the canonical corpus index; proves index self-consistency |
| Index SHA-256 (base64url) | `YLaLsoOJQjHAY2qo1o5wqH-PHc4lpSGRPn0pwjiTRoU` | Raw SHA-256 of the exact canonical index bytes; pinned by the Elixir CLI and the TypeScript verifier core |
| Compiled registry digest | `sha-256:u754joyHGcLCTm1LYV2s6eHauUUdDfJDwwyhbAbxvzc` | The compiled extension registry identity carried in the index |
| Specification digest | `sha-256:JuLNnhAk2rv_kuSoG3HdAKInxKpSftKgNJjhxtlA214` | Domain-separated digest over the canonical manifest of the normative spec set (`spec/`); pinned in release metadata |

A corpus you built yourself that disagrees with the index SHA-256 is not the
certified corpus, however internally consistent it is — both runners refuse
it.

## Corpus layout

The corpus ships at `priv/conformance/`: one canonical `index.json` plus 14
case files under `cases/` (85 certified cases total). Each case file is
`cases/<surface-with-dashes>.json` with the closed members `format`, and
`cases`; each case carries `id`, `surface`, `class`, `input`, and `expect`.
Inputs are exact wire bytes (compact strings, canonical revision text,
descriptor chains); expectations carry either the complete projected output
document for a valid case or the closed error code for an invalid one — a
verdict-only green is refused. Case identifiers are globally unique.

## Runner contract

The certified runner contract is the packaged CLI:

```
charter_agreement_protocol --corpus priv/conformance
```

- Exit `0` — every case recomputed and agreed; the canonical JSON report on
  stdout.
- Exit `1` — load or verification failure.
- Exit `2` — usage.

The canonical report carries exactly: `format`
(`charter-agreement-protocol-conformance-report`), `agreement`,
`exit_status`, `total`, `agreed`, `disagreed`, `corpus_digest`,
`registry_digest`, `index_sha256_base64url`, and `results` — one entry per
case with `id`, `surface`, `agree`, `expected`, and `actual`, where a
verdict document is `{status, output}` for valid cases or
`{status, error_code}` for invalid ones. The wire grammar for the index and
the report is the normative `spec/schemas/corpus-index.json` and
`spec/schemas/corpus-report.json`.

## Byte-agreement procedure for a third implementation

1. Load the corpus directory; reject any index whose raw SHA-256 is not the
   certified index identity above.
2. Independently implement every certified surface: the foundational codecs
   (base64url, JSON decode, canonical JSON encoding, domain-separated
   digests), schema validation, descriptor and descriptor-chain
   verification, revision decode, acceptance verification and equivocation,
   termination verification, chain verification and governing computation,
   and receipt verification — including Ed25519 signature checks over the
   exact RFC 7515 signing-input bytes.
3. Recompute every case's projected output or typed error; compare complete
   documents, not verdicts.
4. Emit the canonical report and compare it byte-for-byte against the
   Elixir runner's report over the same corpus. The repository's
   verifier-agreement gate requires this byte identity over both the
   repository corpus and the corpus unpacked from the package archive, with
   seeded directional reds proving the comparison can fail.

The Node verifier (`verifier/check-corpus.mjs`, run as
`node verifier/check-corpus.mjs priv/conformance`) is the worked reference
for steps 2–4: same canonical JSON encoder rules, same domain separators,
same report serialization, byte-identical to Elixir on all 85 cases.
