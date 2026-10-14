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
| Corpus digest | `sha-256:ZpJFSZnj2-4PGcOdggkwK62YFtCRmQfr_7kKnuwtKL0` |
| Index SHA-256 (base64url) | `xiyty9a_VZTgiIYIKqGZQIAhJB-OQZRIcOX_zyNV-VQ` |
| Extension registry digest | `sha-256:u754joyHGcLCTm1LYV2s6eHauUUdDfJDwwyhbAbxvzc` |
| Specification digest | `sha-256:IJl_oM2je7lE-ZgmScD8_zH_Vn7qrVG8WMXxxsKdIk8` |
| Cases | 541, in 16 case files |

The TypeScript comparisons below run each unchanged executor against all 541
current case inputs and expectations. The pinned build uses its original JSON
reader; the worker build preserves numeric token types. Both were built from
immutable Git snapshots in a temporary directory.

Pinned TypeScript commit `47ef74f02331e6061f50069c2e131eff618cade7`: 338 agree and 203 disagree.

Its certified harness rejects the current index with `uncertified index`;
the executor comparison bypasses only that index and case-file wrapper.

| Case | Expected | Pinned result |
|---|---|---|
| `base64url-decode-null-profile` | `invalid_profile` | `valid` |
| `base64url-decode-null-algorithms` | `invalid_profile` | `valid` |
| `base64url-decode-null-revisions` | `invalid_profile` | `valid` |
| `base64url-decode-kind-mismatch-0` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-1` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-2` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-float` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-string` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-array` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-object` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-null` | `invalid_type` | `valid` |
| `json-decode-null-profile` | `invalid_profile` | `valid` |
| `json-decode-null-algorithms` | `invalid_profile` | `valid` |
| `json-decode-null-revisions` | `invalid_profile` | `valid` |
| `json-incomplete-before-depth` | `invalid_syntax` | `limit_exceeded` |
| `json-input-type-with-valid-limits` | `invalid_type` | `raises` |
| `canonicalization-encode-null-profile` | `invalid_profile` | `valid` |
| `canonicalization-encode-null-algorithms` | `invalid_profile` | `valid` |
| `canonicalization-encode-null-revisions` | `invalid_profile` | `valid` |
| `canonicalization-encode-kind-mismatch-0` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-1` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-2` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-float` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-string` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-array` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-object` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-null` | `invalid_type` | `valid` |
| `digest-hash-null-profile` | `invalid_profile` | `valid` |
| `digest-hash-null-algorithms` | `invalid_profile` | `valid` |
| `digest-hash-null-revisions` | `invalid_profile` | `valid` |
| `schema-validate-null-profile` | `invalid_profile` | `valid` |
| `schema-validate-null-algorithms` | `invalid_profile` | `valid` |
| `schema-validate-null-revisions` | `invalid_profile` | `valid` |
| `schema-validate-kind-mismatch-0` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-1` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-2` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-float` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-string` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-array` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-object` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-null` | `invalid_type` | `valid` |
| `party_descriptor-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `party_descriptor-verify-float-descriptor-number` | `invalid_type` | `non_canonical_bytes` |
| `party_descriptor-verify-float-revision-minimum` | `invalid_profile` | `valid` |
| `party_descriptor-verify-float-revision-maximum` | `invalid_profile` | `valid` |
| `party_descriptor-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `descriptor_chain-verify-null-profile` | `invalid_profile` | `valid` |
| `descriptor_chain-verify-null-algorithms` | `invalid_profile` | `valid` |
| `descriptor_chain-verify-null-revisions` | `invalid_profile` | `valid` |
| `descriptor_chain-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `charter_revision-decode-null-profile` | `invalid_profile` | `valid` |
| `charter_revision-decode-null-algorithms` | `invalid_profile` | `valid` |
| `charter_revision-decode-null-revisions` | `invalid_profile` | `valid` |
| `revision-no-bindings` | `valid` | `raises` |
| `revision-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `revision-float-revision-number` | `invalid_type` | `non_canonical_bytes` |
| `revision-float-release-number` | `invalid_type` | `non_canonical_bytes` |
| `charter_revision-decode-kind-mismatch-0` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-1` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-2` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-float` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-string` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-array` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-object` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-null` | `invalid_type` | `valid` |
| `acceptance-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `acceptance-verify-float-revision-number` | `invalid_type` | `non_canonical_bytes` |
| `acceptance-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `acceptance-equivocation-null-profile` | `invalid_profile` | `valid` |
| `acceptance-equivocation-null-algorithms` | `invalid_profile` | `valid` |
| `acceptance-equivocation-null-revisions` | `invalid_profile` | `valid` |
| `acceptance-equivocation-kind-mismatch-0` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-1` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-2` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-float` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-string` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-array` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-object` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-null` | `invalid_type` | `valid` |
| `termination-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `termination-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `chain-verify-null-profile` | `invalid_profile` | `valid` |
| `chain-verify-null-algorithms` | `invalid_profile` | `valid` |
| `chain-verify-null-revisions` | `invalid_profile` | `valid` |
| `chain-verify-empty-revisions-malformed-descriptor` | `compact_invalid` | `chain_invalid` |
| `chain-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `chain-verify_profile-null-profile` | `invalid_profile` | `raises` |
| `chain-verify_profile-null-algorithms` | `invalid_profile` | `invalid_type` |
| `chain-verify_profile-null-revisions` | `invalid_profile` | `invalid_type` |
| `chain-verify_profile-float-revision-minimum` | `invalid_profile` | `valid` |
| `chain-verify_profile-float-revision-maximum` | `invalid_profile` | `valid` |
| `chain-verify_profile-kind-mismatch-0` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-1` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-2` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-float` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-string` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-array` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-object` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-null` | `invalid_type` | `valid` |
| `governing_revision-null-profile` | `invalid_profile` | `valid` |
| `governing_revision-null-algorithms` | `invalid_profile` | `valid` |
| `governing_revision-null-revisions` | `invalid_profile` | `valid` |
| `governing-zero-byte-limit` | `limit_exceeded` | `governing_invalid` |
| `governing_revision-kind-mismatch-0` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-1` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-2` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-float` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-string` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-array` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-object` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-null` | `invalid_type` | `valid` |
| `receipt-strict-chain-limits` | `limit_exceeded` | `valid` |
| `receipt-artifact-byte-over-limit` | `limit_exceeded` | `valid` |
| `receipt-empty-revisions-top-limits-items` | `limit_exceeded` | `chain_invalid` |
| `receipt-empty-revisions-top-limits-bytes` | `limit_exceeded` | `chain_invalid` |
| `receipt-empty-revisions-top-limits-artifact-bytes` | `limit_exceeded` | `chain_invalid` |
| `receipt-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `receipt-verify-float-revision-number` | `invalid_type` | `non_canonical_bytes` |
| `receipt-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `receipt-chain-view-limits` | `invalid_type` | `valid` |
| `receipt-chain-view-null-limits` | `invalid_type` | `valid` |
| `receipt-chain-view-extra` | `invalid_type` | `valid` |
| `receipt-chain-view-profile` | `invalid_type` | `valid` |
| `signing-set-profile-scope` | `valid` | `algorithm_outside_profile` |
| `signing-termination-counterparty-profile` | `valid` | `algorithm_outside_profile` |
| `signing-ed25519-no-curve-point` | `signing_key_invalid` | `valid` |
| `signing-prepare-null-profile` | `invalid_profile` | `valid` |
| `signing-prepare-empty-revisions-malformed-descriptor` | `compact_invalid` | `chain_invalid` |
| `signing-ed25519-party_descriptor-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-mldsa65-party_descriptor-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-ed25519-party_descriptor-float-descriptor-number` | `signing_input_invalid` | `valid` |
| `signing-mldsa65-party_descriptor-float-descriptor-number` | `signing_input_invalid` | `valid` |
| `signing-ed25519-acceptance-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-mldsa65-acceptance-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-ed25519-acceptance-float-revision-number` | `signing_input_invalid` | `valid` |
| `signing-mldsa65-acceptance-float-revision-number` | `signing_input_invalid` | `valid` |
| `signing-ed25519-termination-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-mldsa65-termination-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-ed25519-receipt-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-mldsa65-receipt-float-protocol-revision` | `signing_input_invalid` | `valid` |
| `signing-ed25519-receipt-float-revision-number` | `signing_input_invalid` | `valid` |
| `signing-mldsa65-receipt-float-revision-number` | `signing_input_invalid` | `valid` |
| `signing-prepare-float-revision-minimum` | `invalid_profile` | `valid` |
| `signing-prepare-float-revision-maximum` | `invalid_profile` | `valid` |
| `signing-receipt-chain-view-limits` | `invalid_type` | `limit_exceeded` |
| `signing-receipt-chain-view-null-limits` | `invalid_type` | `invalid_limits` |
| `signing-receipt-chain-view-extra` | `invalid_type` | `valid` |
| `signing-receipt-chain-view-profile` | `invalid_type` | `valid` |

Worker TypeScript commit `2876831ba3f8cdaa8a147ea47d3ae47a15711dd3`: 406 agree and 135 disagree.

| Case | Expected | Worker result |
|---|---|---|
| `base64url-decode-kind-mismatch-0` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-1` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-2` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-float` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-string` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-array` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-object` | `invalid_type` | `valid` |
| `base64url-decode-kind-mismatch-null` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-0` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-1` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-2` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-float` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-string` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-array` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-object` | `invalid_type` | `valid` |
| `canonicalization-encode-kind-mismatch-null` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-0` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-1` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-2` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-float` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-string` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-array` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-object` | `invalid_type` | `valid` |
| `schema-validate-kind-mismatch-null` | `invalid_type` | `valid` |
| `party_descriptor-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `party_descriptor-verify-float-descriptor-number` | `invalid_type` | `non_canonical_bytes` |
| `party_descriptor-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `party_descriptor-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `descriptor_chain-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `revision-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `revision-float-revision-number` | `invalid_type` | `non_canonical_bytes` |
| `revision-float-release-number` | `invalid_type` | `non_canonical_bytes` |
| `charter_revision-decode-kind-mismatch-0` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-1` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-2` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-float` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-string` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-array` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-object` | `invalid_type` | `valid` |
| `charter_revision-decode-kind-mismatch-null` | `invalid_type` | `valid` |
| `acceptance-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `acceptance-verify-float-revision-number` | `invalid_type` | `non_canonical_bytes` |
| `acceptance-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `acceptance-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-0` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-1` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-2` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-float` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-string` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-array` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-object` | `invalid_type` | `valid` |
| `acceptance-equivocation-kind-mismatch-null` | `invalid_type` | `valid` |
| `termination-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `termination-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `termination-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `chain-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-0` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-1` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-2` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-float` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-string` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-array` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-object` | `invalid_type` | `valid` |
| `chain-verify_profile-kind-mismatch-null` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-0` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-1` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-2` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-float` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-string` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-array` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-object` | `invalid_type` | `valid` |
| `governing_revision-kind-mismatch-null` | `invalid_type` | `valid` |
| `receipt-verify-float-protocol-revision` | `invalid_type` | `non_canonical_bytes` |
| `receipt-verify-float-revision-number` | `invalid_type` | `non_canonical_bytes` |
| `receipt-verify-kind-mismatch-0` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-1` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-2` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-float` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-string` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-boolean` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-array` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-object` | `invalid_type` | `valid` |
| `receipt-verify-kind-mismatch-null` | `invalid_type` | `valid` |
| `receipt-chain-view-limits` | `invalid_type` | `valid` |
| `receipt-chain-view-null-limits` | `invalid_type` | `valid` |
| `receipt-chain-view-extra` | `invalid_type` | `valid` |
| `receipt-chain-view-profile` | `invalid_type` | `valid` |
| `signing-receipt-chain-view-limits` | `invalid_type` | `limit_exceeded` |
| `signing-receipt-chain-view-null-limits` | `invalid_type` | `invalid_limits` |
| `signing-receipt-chain-view-extra` | `invalid_type` | `valid` |
| `signing-receipt-chain-view-profile` | `invalid_type` | `valid` |

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
