# Protocol foundation

This document defines the implemented byte-level, schema-validation, and corpus
foundation of Charter Agreement Protocol. Artifact-specific schemas, signatures,
chain evaluation, and conformance reports are not part of this surface yet.

## Tagged JSON values

`CharterAgreementProtocol.Json.decode/1` returns exactly one of these values:

- `:null`
- `{:boolean, boolean}`
- `{:integer, integer}`
- `{:float, float}`
- `{:string, utf8_binary}`
- `{:array, values}`
- `{:object, [{utf8_name, value}]}`

The decoder rejects duplicate object names, trailing non-whitespace bytes,
invalid UTF-8, I-JSON noncharacters, malformed syntax, numbers that cannot
round-trip through an ECMAScript double, and non-binary input. Errors do not
contain rejected input.

`Json.decode/2` accepts a caller-supplied `%CharterAgreementProtocol.Limits{}`.
Limits are pure data and are validated before parsing; no environment or
application configuration participates. The defaults and greatest selectable
values are:

| Ceiling | Default | Greatest value |
|---|---:|---:|
| input bytes | 1,048,576 | 16,777,216 |
| nesting depth | 64 | 128 |
| members per object | 1,024 | 65,536 |
| items per array | 4,096 | 65,536 |
| decoded bytes per string or member name | 65,536 | 1,048,576 |

Container counts are per container. String limits apply after JSON unescaping and
count UTF-8 bytes. The exact bound is accepted; maximum plus one returns the
value-free `:limit_exceeded` error.

## Canonical JSON

`CharterAgreementProtocol.Canonicalization.encode/1` implements RFC 8785 JSON
Canonicalization Scheme over the tagged algebra:

- object names sort by unsigned UTF-16 code units;
- strings use the shortest required JSON escapes, reject I-JSON noncharacters,
  and are not Unicode-normalized;
- numbers use ECMAScript shortest-round-trip spelling;
- output contains no inter-token whitespace.

`verify/1` decodes received bytes, re-encodes the value, and returns it only when
the re-encoded bytes are identical. Semantic JSON equivalence is not canonical
byte equivalence.

## Base64url

`CharterAgreementProtocol.Base64Url` emits and accepts only the unpadded URL-safe
alphabet. Padding, impossible lengths, alphabet violations, and non-zero pad bits
are rejected. Decoding re-encodes the result and requires byte-for-byte equality.

## Digests

`CharterAgreementProtocol.Digest.hash/2` computes:

```text
SHA-256(domain-separator || 0x00 || content-bytes)
```

The closed domain set covers party descriptors, charter revisions, acceptances,
terminations, receipts, legal text, signatures, extension schemas, the extension
registry, conformance reports, and the corpus index. Unknown domains are internal
programming errors and fail loudly.

The wire form is `sha-256:` followed by 43 unpadded base64url characters.
Comparison requires equal algorithm and width, consumes every byte pair through
one XOR/OR accumulator, and tests the accumulator only after the full input.

## Typed errors

Public decode and verification failures return
`%CharterAgreementProtocol.Error{code, subject, detail}`. The code vocabulary is
closed. Subjects contain protocol-owned names and non-negative indexes, never
rejected values. Details are absent or a protocol-owned atom/string. Architecture
gates reject undeclared production emissions, declared codes with no production
emission site, constructor aliases/imports that could evade the scan, and dynamic
production detail values.

## Closed schema validation

`CharterAgreementProtocol.Schema` consumes protocol-owned field tables. A field
declares requiredness, tagged value types, a closed declarative constraint,
collection cardinality, and optional nested object or array-item definitions.
Definitions may carry closed declarative cross-field rules. Schema definitions
contain no functions and cannot call host or application code.

The engine completes seven stages in this exact order:

1. unknown member;
2. missing required member;
3. tagged type;
4. field constraint;
5. cardinality;
6. nested definition;
7. cross-field rule.

Same-stage selection follows field declaration order, never received object
member order. Nested failures are reported at the outer schema field. Subjects
contain only definition and field names from the protocol-owned table.

## Conformance corpus integrity

`CharterAgreementProtocol.Conformance.Corpus.load/1` is pure: it accepts a complete
`%{relative_path => bytes}` map and performs no file I/O. Loading requires:

- canonical index and case-file bytes;
- a recomputed, domain-separated in-index corpus digest;
- exact declared/observed file-set equality and per-file SHA-256 hashes;
- exact per-file and total case counts;
- closed non-empty case shapes and globally unique case IDs;
- a compiled surface/class applicability floor whose required counts equal
  observations and whose not-applicable cells carry non-empty reasons; and
- projected outputs for valid cases, so a verdict-only green is refused.

The shipped foundational corpus contains real codec, digest, bounded-decode, and
schema inputs. `verifier/check-corpus.mjs` independently checks the same bytes with
Node 24 or newer using only `node:` built-ins. A corrupt index must exit nonzero.
The Node harness is repository-side verification code and is intentionally absent
from the Hex archive; `priv/conformance` is included.

## Architecture boundaries

Production runtime code uses only OTP `:crypto`. Corpus loading is in-memory and
does not read files. All Mix dependencies are development/test-only and
`runtime: false`. The build rejects host, transport, database,
private-authority-runtime, and application-callback coupling.

Protocol evolution is carried as digest-covered data. Version tokens are rejected
from durable paths and identifiers; the exact Hex package `source_ref` is the only
allowlisted identity.
