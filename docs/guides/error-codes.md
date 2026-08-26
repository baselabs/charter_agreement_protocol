# Error codes

CAP never authorizes.

Every verification failure is one closed, value-free error code from
`CharterAgreementProtocol.Error.codes/0` — 57 codes, each carrying only a
protocol-owned subject, never the rejected input. This reference states each
code's evidence truthfully:

- **corpus-exercised** — a certified corpus case expects exactly this code,
  so its rejection behavior is certified negative evidence.
- **test-exercised** — in-repo tests drive the code through the public API.
  Eleven codes in this class are structurally outside case certification:
  the eight `corpus_*` loader codes fire while loading the corpus a case
  must load; `signing_input_invalid` and `signing_refused` fire on producer
  seams the runner does not expose; `governing_invalid` fires only on a
  non-timestamp query argument the runner cannot pass; and
  `extension_schema_digest_mismatch` fires only through the explicit
  schema-view test seam — the compiled registry is self-consistent by
  construction.
- **declared** — the code is in the compiled production vocabulary (the
  architecture vocabulary census asserts the emitted set equals the declared
  set) but no dedicated case drives it yet.

Closing the corpus-coverage gap further is a future certification decision.

| Code | Coverage | Evidence |
|---|---|---|
| `:acceptance_claims_mismatch` | corpus-exercised | certified corpus expectations (1 case) |
| `:acceptance_equivocation_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:acceptance_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:base64url_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:base64url_padded` | corpus-exercised | certified corpus expectations (1 case) |
| `:cardinality_violation` | corpus-exercised | certified corpus expectations (2 cases) |
| `:chain_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:compact_invalid` | corpus-exercised | certified corpus expectations (2 cases) |
| `:constraint_violation` | corpus-exercised | certified corpus expectations (2 cases) |
| `:corpus_applicability_incomplete` | test-exercised | corpus_test |
| `:corpus_case_id_duplicate` | test-exercised | corpus_test |
| `:corpus_case_invalid` | test-exercised | corpus_test |
| `:corpus_count_mismatch` | test-exercised | corpus_test |
| `:corpus_empty` | test-exercised | corpus_test |
| `:corpus_file_set_mismatch` | test-exercised | corpus_test |
| `:corpus_hash_mismatch` | test-exercised | corpus_test |
| `:corpus_index_invalid` | test-exercised | corpus_test |
| `:cross_field_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:descriptor_chain_invalid` | corpus-exercised | certified corpus expectations (2 cases) |
| `:descriptor_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:descriptor_key_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:digest_algorithm_unsupported` | corpus-exercised | certified corpus expectations (1 case) |
| `:digest_encoding_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:digest_mismatch` | corpus-exercised | certified corpus expectations (1 case) |
| `:duplicate_member` | corpus-exercised | certified corpus expectations (2 cases) |
| `:extension_criticality_conflict` | corpus-exercised | certified corpus expectations (1 case) |
| `:extension_duplicate` | corpus-exercised | certified corpus expectations (1 case) |
| `:extension_namespace_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:extension_retired` | corpus-exercised | certified corpus expectations (1 case) |
| `:extension_schema_digest_mismatch` | test-exercised | extension_test |
| `:extension_schema_unavailable` | corpus-exercised | certified corpus expectations (1 case) |
| `:extension_scope_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:extension_unknown_critical` | corpus-exercised | certified corpus expectations (1 case) |
| `:governing_invalid` | test-exercised | chain_test |
| `:integer_magnitude` | corpus-exercised | certified corpus expectations (1 case) |
| `:invalid_encoding` | corpus-exercised | certified corpus expectations (2 cases) |
| `:invalid_limits` | corpus-exercised | certified corpus expectations (1 case) |
| `:invalid_number` | corpus-exercised | certified corpus expectations (1 case) |
| `:invalid_syntax` | corpus-exercised | certified corpus expectations (1 case) |
| `:invalid_type` | corpus-exercised | certified corpus expectations (4 cases) |
| `:limit_exceeded` | corpus-exercised | certified corpus expectations (1 case) |
| `:missing_required` | corpus-exercised | certified corpus expectations (2 cases) |
| `:nested_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:non_canonical_bytes` | corpus-exercised | certified corpus expectations (1 case) |
| `:number_not_double_expressible` | corpus-exercised | certified corpus expectations (1 case) |
| `:protected_header_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:receipt_claims_mismatch` | corpus-exercised | certified corpus expectations (1 case) |
| `:receipt_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:revision_invalid` | corpus-exercised | certified corpus expectations (3 cases) |
| `:signature_invalid` | corpus-exercised | certified corpus expectations (4 cases) |
| `:signing_input_invalid` | test-exercised | signing_input_test |
| `:signing_refused` | test-exercised | signing_input_test |
| `:termination_claims_mismatch` | corpus-exercised | certified corpus expectations (1 case) |
| `:termination_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:timestamp_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:trailing_bytes` | corpus-exercised | certified corpus expectations (1 case) |
| `:unknown_member` | corpus-exercised | certified corpus expectations (2 cases) |
