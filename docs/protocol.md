# Foundational byte contract

This document defines the implemented byte-level foundation of Charter Agreement
Protocol. Artifact schemas, signatures, chain evaluation, and conformance reports
are not part of this surface yet.

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
invalid UTF-8, malformed syntax, numbers that cannot round-trip through an
ECMAScript double, and non-binary input. Errors do not contain rejected input.

## Canonical JSON

`CharterAgreementProtocol.Canonicalization.encode/1` implements RFC 8785 JSON
Canonicalization Scheme over the tagged algebra:

- object names sort by unsigned UTF-16 code units;
- strings use the shortest required JSON escapes and are not Unicode-normalized;
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

## Architecture boundaries

Production runtime code uses only OTP `:crypto`. All Mix dependencies are
development/test-only and `runtime: false`. The build rejects host, transport,
database, private-authority-runtime, and application-callback coupling.

Protocol evolution is carried as digest-covered data. Version tokens are rejected
from durable paths and identifiers; the exact Hex package `source_ref` is the only
allowlisted identity.
