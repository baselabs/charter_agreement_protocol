# Error codes

CAP never authorizes.

Every verification failure is one closed, value-free error code from
`CharterAgreementProtocol.Error.codes/0` — 57 codes, each carrying only a
protocol-owned subject, never the rejected input. This reference states each
code's evidence truthfully:

- **corpus-exercised** — a certified corpus case expects exactly this code,
  so its rejection behavior is certified negative evidence.
- **test-exercised** — in-repo tests drive the code through the public API
  (no certified corpus case yet).
- **declared** — the code is in the compiled production vocabulary (the
  architecture vocabulary census asserts the emitted set equals the declared
  set) but no dedicated case drives it yet.

Closing the corpus-coverage gap for the test-exercised and declared codes is
a future certification decision, deliberately not taken here.

| Code | Coverage | Evidence |
|---|---|---|
| `:acceptance_claims_mismatch` | corpus-exercised | certified corpus expectations (1 case) |
| `:acceptance_equivocation_invalid` | test-exercised | acceptance_test |
| `:acceptance_invalid` | test-exercised | acceptance_test |
| `:base64url_invalid` | test-exercised | base64url_test |
| `:base64url_padded` | corpus-exercised | certified corpus expectations (1 case) |
| `:cardinality_violation` | corpus-exercised | certified corpus expectations (2 cases) |
| `:chain_invalid` | test-exercised | chain_test, corpus_test |
| `:compact_invalid` | test-exercised | chain_test, party_descriptor_test, signing_input_test |
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
| `:descriptor_invalid` | declared | compiled vocabulary; no dedicated case yet |
| `:descriptor_key_invalid` | test-exercised | party_descriptor_test |
| `:digest_algorithm_unsupported` | test-exercised | digest_test |
| `:digest_encoding_invalid` | test-exercised | digest_test |
| `:digest_mismatch` | corpus-exercised | certified corpus expectations (1 case) |
| `:duplicate_member` | test-exercised | canonicalization_test, json_test |
| `:extension_criticality_conflict` | test-exercised | extension_test |
| `:extension_duplicate` | test-exercised | extension_test |
| `:extension_namespace_invalid` | test-exercised | extension_test |
| `:extension_retired` | test-exercised | extension_test |
| `:extension_schema_digest_mismatch` | test-exercised | extension_test |
| `:extension_schema_unavailable` | test-exercised | extension_test |
| `:extension_scope_invalid` | test-exercised | extension_test, profile_extension_integration_test |
| `:extension_unknown_critical` | corpus-exercised | certified corpus expectations (1 case) |
| `:governing_invalid` | test-exercised | chain_test |
| `:integer_magnitude` | test-exercised | canonicalization_test |
| `:invalid_encoding` | corpus-exercised | certified corpus expectations (2 cases) |
| `:invalid_limits` | test-exercised | acceptance_test, chain_test, charter_revision_test, descriptor_chain_test, json_limits_test, limits_test, party_descriptor_test, receipt_test, signing_input_test, termination_notice_test |
| `:invalid_number` | test-exercised | json_test |
| `:invalid_syntax` | test-exercised | chain_test, json_test, receipt_test |
| `:invalid_type` | corpus-exercised | certified corpus expectations (4 cases) |
| `:limit_exceeded` | corpus-exercised | certified corpus expectations (1 case) |
| `:missing_required` | corpus-exercised | certified corpus expectations (2 cases) |
| `:nested_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:non_canonical_bytes` | corpus-exercised | certified corpus expectations (1 case) |
| `:number_not_double_expressible` | test-exercised | json_test |
| `:protected_header_invalid` | test-exercised | party_descriptor_test |
| `:receipt_claims_mismatch` | test-exercised | receipt_test |
| `:receipt_invalid` | test-exercised | receipt_test |
| `:revision_invalid` | corpus-exercised | certified corpus expectations (3 cases) |
| `:signature_invalid` | corpus-exercised | certified corpus expectations (4 cases) |
| `:signing_input_invalid` | test-exercised | signing_input_test |
| `:signing_refused` | test-exercised | signing_input_test |
| `:termination_claims_mismatch` | corpus-exercised | certified corpus expectations (1 case) |
| `:termination_invalid` | corpus-exercised | certified corpus expectations (1 case) |
| `:timestamp_invalid` | test-exercised | timestamp_test |
| `:trailing_bytes` | test-exercised | json_test |
| `:unknown_member` | corpus-exercised | certified corpus expectations (2 cases) |
