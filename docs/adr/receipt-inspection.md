# Receipt inspection

CAP never authorizes.

Receipt verification establishes whether a receipt can be verified in a supplied
view. An audit also needs the exact signed material, the key used, and separate
answers for grant digest equality and agreement with the governing revision.
Expose those answers through `inspect_receipt` in Elixir and `inspectReceipt`
in TypeScript. Both take raw retained chain artifacts and an optional tagged
grant digest supplied by the caller. The browser calls the TypeScript operation
with the same inputs.

Inspection reuses chain verification, receipt admission, and issuer signature
and holder checks. It returns the existing error code if any check fails.
`invalid_type` covers an invalid input type and `digest_encoding_invalid`
covers a malformed tagged grant digest. Grant and governing comparisons
produce evidence in a successful inspection.

The result has five records.

- `signed` holds the protected, payload, and signature segments in their
  received form. The protected and payload segment digests are tagged SHA-256
  of the respective ASCII segments. `receipt_digest` retains the existing
  domain-separated digest of the decoded payload bytes.
- `claims` holds the bounded receipt claims, including extension values and
  the timestamp strings as decoded.
- `provenance` holds the charter ID, revision digest and number, issuing role,
  key ID, algorithm, and thumbprint of the key that verified the signature.
  `revision_status` is `verified` for a named accepted revision and
  `not_verified` otherwise. `scope_status` uses the signer-scope rule
  against the named accepted revision.
- `grant` compares the claim's digest and the supplied reference digest.
  `matches` and `differs` report equality. `not_verified` has reason
  `receipt_grant_digest_missing` when the claim has no digest, or
  `grant_reference_missing` when the caller supplied none.
- `agreement` compares the claim with the unique revision governing at
  `occurred_at`. It names that revision and returns `matches` or `differs`,
  with differing claim fields in bytewise order. It returns `not_verified`
  with `no_governing_revision` or `contested_governing_revision` when the
  view supplies no unique governing revision.

The result also carries the standard verification omission floor.
Segment strings and digests can be exported as JSON for later comparison.
An exported result contains receipt evidence and inherits the handling
requirements of the original receipt.
