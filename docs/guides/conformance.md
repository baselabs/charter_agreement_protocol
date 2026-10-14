# The conformance corpus

The conformance corpus is a fixed set of test cases. Each case gives exact input bytes
and the exact result CAP returns for them: the full output for a valid case, the error
code for an invalid one. Two implementations that agree on every case agree on those
inputs. The corpus is finite, so passing it does not prove an implementation meets
every requirement in the [specification](../../spec/core.md); a conforming
implementation must meet both.

The corpus ships in the Hex package at `priv/conformance`, so you can run it against
the copy you installed. To run it or to build a second implementation against it, see
[Implement CAP in another language](implementing.md).

## Identities

These values identify the corpus and the specification this release ships. This table
is the one place in the guides where they are recorded.

| Identity | Value |
|---|---|
| Corpus digest | `sha-256:s6oQr7zRm9quErCZw__yQPsv63fNj8CKdOk_3o3o6hM` |
| Index SHA-256 (base64url) | `VwaA08scgt5MTLY-WrQbwCShxnvPbEmkpmd0kBUKjgw` |
| Extension registry digest | `sha-256:u754joyHGcLCTm1LYV2s6eHauUUdDfJDwwyhbAbxvzc` |
| Specification digest | `sha-256:Po0YxdnQioE02JC5tbC3Vr1I5wpeT9aiy0e4xTGegZM` |
| Cases | 243, in 16 case files |

The pinned TypeScript build `47ef74f` certifies an earlier index. Its case
executor differs on four current cases: `receipt-strict-chain-limits`,
`signing-set-profile-scope`, `signing-termination-counterparty-profile` and
`signing-ed25519-no-curve-point`. Its harness also rejects the current
receipt limit applicability cell. The agreement and release checks report
this retained pin's corpus mismatch.

What each one tells you:

- **Corpus digest.** A domain-separated digest computed over the index itself, with
  its own `corpus_digest` member left out. It binds the index bytes, including the
  file hashes and counts the index lists. It does not check them: the loader
  separately checks that each case file matches its listed hash and that the counts
  add up. Anyone can build a new index and compute its digest, so this value alone
  does not identify the released corpus.
- **Index SHA-256.** The plain SHA-256 of the exact `index.json` bytes. This is the
  value that identifies the released corpus. The Elixir CLI refuses any corpus whose
  index has a different SHA-256, and so does the TypeScript verifier.
- **Extension registry digest.** The digest of the extension registry compiled into
  the package. The index carries it, and the loader refuses an index whose value
  differs from the compiled registry.
- **Specification digest.** A digest over every file under `spec/`: path, byte length
  and SHA-256 of each. It ties a release to the exact specification text it ships.
  The corpus does not carry it; the release metadata does.

`priv/release-metadata.json` records all four, together with the default and maximum
[limits](limits-and-profiles.md), the signature algorithm registry, and the
verification semantics version. [Upgrade and persist verification
identity](upgrading-verification-identity.md) explains how to store these values
next to a verdict.

## What the corpus covers

Every case names a surface (the operation it runs) and a class (the kind of
behavior it exercises). The surfaces:

| Surface | What it runs |
|---|---|
| `base64url.decode` | The unpadded base64url decoder |
| `json.decode` | The bounded JSON decoder and its tagged values |
| `canonicalization.encode` | Canonical JSON encoding and the canonical-bytes check |
| `digest.hash` | Domain-separated SHA-256 digests and digest comparison |
| `schema.validate` | Closed schema validation, stage by stage |
| `party_descriptor.verify` | One party descriptor |
| `descriptor_chain.verify` | A descriptor history, including forks and superseded descriptors |
| `charter_revision.decode` | One charter revision |
| `acceptance.verify` | One acceptance against its revision and descriptor history |
| `acceptance.equivocation` | Two acceptances by one signer over different revisions at one number |
| `termination.verify` | One termination notice |
| `chain.verify` | A whole artifact set: acceptance pairing, forks, supersession, size bounds |
| `chain.verify_profile` | A whole artifact set under a capability profile |
| `governing_revision` | The governing revision at given instants, including closure by termination |
| `receipt.verify` | One receipt against a verified chain or a bare revision |
| `signing.prepare` | Pre-sign segments, descriptor key match, and typed refusals |

Unknown `limits` and `profile` members return `invalid_limits` and
`invalid_profile`, as the library constructors do. The `receipt.verify` runner
applies the case's `limits` to its context and receipt.

The classes run from `valid` and the size bounds (`exact_bound`, `maximum_plus_one`)
through each kind of malformed input to the set-level outcomes: `chain_fork`,
`equivocation`, `supersession`, `terminated` and others. The index records, for every
surface and class, either how many cases exercise that pair or why the pair does not
apply. The package compiles its own list of the pairs that each surface must cover,
and a corpus missing any of them does not load.

Signed cases include Ed25519 and ML-DSA signatures. Several receipt and profile cases
carry fixed vectors from the [sibling protocol](receipts.md) packages, and the
repository's tests check CAP's digests for those vectors against the published
packages.

## The requirements matrix

Each requirement in the specification carries a stable identifier of the form
`CAP-<SURFACE>-<tag>`, for example `CAP-CHAIN-contested-refusal`. The [requirements
matrix](../../spec/requirements.md) lists, for each identifier, the corpus cells,
tests and named source mutations that check it. The matrix is generated from
`CharterAgreementProtocol.RequirementMap`, and the corpus check fails if the matrix is
stale, if a requirement has no evidence, or if a corpus cell or mutation is bound to
no requirement.

## Changes to the corpus

A change to any case changes the index bytes, so it changes the index SHA-256 and the
corpus digest, and a new release records the new values here. A correction that
changes a verdict under an already published protocol revision follows the [errata
policy](../errata.md).

## Contributing

Contributors who change the corpus, the registry or the specification also re-record
these identities and rerun the full set of repository checks. The steps and the
commands are in [CONTRIBUTING](../../CONTRIBUTING.md).
