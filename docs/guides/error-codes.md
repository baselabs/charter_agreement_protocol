# Handle errors

Every CAP decode, verify, signing-input and assembly function that can fail returns
`{:error, %CharterAgreementProtocol.Error{}}`. A few low-level helpers raise on misuse
instead, and their docs say so, for example `Digest.hash/2` with an unknown domain. The
error has three fields:

- `code`: one atom from a closed set. `CharterAgreementProtocol.Error.codes/0`
  lists all of them, and this page explains each one.
- `subject`: a list of protocol names and indexes that says where the failure
  is, such as `["compact_jws", "signature"]` or `["receipt", "claims"]`.
- `detail`: reserved; `nil` in this release.

None of the fields of an error CAP returns carries the input that failed, so you can
log all of them.

```elixir
alias CharterAgreementProtocol, as: CAP
alias CharterAgreementProtocol.{Error, Limits}

handle = fn
  {:ok, facts} ->
    {:ok, facts}

  {:error, %Error{code: :algorithm_unsupported_on_substrate}} ->
    :verify_on_a_capable_runtime

  {:error, %Error{code: code} = error} when code in [:invalid_limits, :invalid_profile] ->
    raise ArgumentError, "bad CAP configuration: #{code} at #{Enum.join(error.subject, ".")}"

  {:error, %Error{code: code}} ->
    {:rejected, code}
end

result = handle.(CAP.decode_charter_revision(~s({"protocol_revision":2}), Limits.default()))
```

`result` is `{:rejected, :missing_required}`: the revision has no
`revision_number`.

Most codes mean the same thing to your application: do not rely on this
input, and tell whoever sent it. The tables say when a code points somewhere
else: at your own call or configuration, at the runtime, or at claims you are
about to sign.

## How to read the tables

- **Reject the input.** The artifact or its bytes are wrong. Keep the error
  for your audit log and report it to the sender. Do not repair the bytes and
  verify again: a signature and a digest cover the exact bytes.
- **Fix your call.** Your code passed something CAP cannot use. The input may
  be fine.
- **Fix the claims.** A signing input refused the claims you gave it. Nothing
  was signed.

## Encoding

Bytes that are not strict base64url, JSON, canonical JSON, tagged digests or
UTC timestamps.

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:base64url_invalid` | a segment is not unpadded URL-safe base64 | `+` or `/` from standard Base64, a stray character, or a value that does not re-encode to the same text | reject the input |
| `:base64url_padded` | a segment ends in `=` padding | an encoder with padding turned on | reject the input |
| `:invalid_syntax` | the bytes are not JSON | truncated or hand-edited bytes | reject the input |
| `:invalid_encoding` | the bytes are not UTF-8, or a string holds a Unicode noncharacter | binary data where text belongs | reject the input; when producing, remove the character |
| `:invalid_number` | a number does not fit a double | an exponent such as `1e400` | reject the input |
| `:number_not_double_expressible` | a number token cannot be a canonical double spelling | an integer above 2^53 − 1 that is not the exact spelling of a double, an integer token longer than 21 digits, or a fractional or exponent token longer than 32 bytes | reject the input |
| `:duplicate_member` | an object names the same member twice | a serializer that does not merge keys | reject the input |
| `:trailing_bytes` | bytes follow the JSON value | two values in one field, or a leading zero such as `01` | reject the input |
| `:non_canonical_bytes` | valid JSON, but not in canonical form | bytes re-serialized by a JSON library: other member order, spacing or number spelling | reject the input; produce revisions with `encode_charter_revision/1` |
| `:integer_magnitude` | an integer you are encoding is outside ±(2^53 − 1) | a counter or amount too large for I-JSON | fix the claims |
| `:digest_algorithm_unsupported` | a tagged digest names an algorithm other than `sha-256` | `sha-512:...` | reject the input |
| `:digest_encoding_invalid` | the text has no `algorithm:` prefix, or the text after `sha-256:` is not 43 base64url characters for 32 bytes | a bare hash with no prefix, a hex digest, or a truncated one | reject the input |
| `:digest_mismatch` | `Digest.verify_content/3` found bytes that do not hash to the digest | content changed after its digest was taken | reject the input |
| `:timestamp_invalid` | a timestamp is not an exact UTC RFC 3339 instant | an offset such as `+00:00`, a lowercase `t`, an impossible date, or second 60 at any time other than 23:59 on June 30 or December 31 (CAP checks that rule only and does not consult a leap-second table) | reject the input; producers write `YYYY-MM-DDTHH:MM:SSZ` |

The three digest codes come from the `Digest` functions. Inside an artifact,
a malformed digest member fails the schema instead (`:constraint_violation`,
or `:nested_invalid` inside a nested object), and a digest that names the
wrong artifact is a claims mismatch.

## Claims and members

Each artifact has a closed schema. These codes say which rule a member broke;
the subject names the schema, and the member when there is one.

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:invalid_type` | a value has the wrong type | a string where a number belongs, or your code passed the wrong Elixir term (a non-list for a list of artifacts, a string for a governing instant) | reject the input; if the subject names your argument, fix your call |
| `:unknown_member` | a member the schema does not define | an extra claim, or data meant for the `extensions` envelope | reject the input |
| `:missing_required` | a required member is absent | an incomplete producer | reject the input |
| `:constraint_violation` | a value is outside its allowed form | a `protocol_revision` outside 1 to 3, a value outside its enumeration, a string too long or too short, a digest that does not match the `sha-256:` pattern | reject the input |
| `:cardinality_violation` | a list has too few or too many items | a revision with one or three parties, or more than 32 extensions | reject the input |
| `:nested_invalid` | a nested object or list item breaks its own schema | a bad entry inside `parties`, `verification_keys` or `grant` | reject the input |
| `:cross_field_invalid` | members are valid alone but not together | a receipt `decision` and `outcome` pair outside the allowed set, or an extension body whose floor is above its cap | reject the input |

## Envelope and signature

Signed artifacts are attached compact JWS strings.

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:compact_invalid` | not three dot-separated segments, or a header or payload segment does not decode | a detached or truncated JWS | reject the input |
| `:protected_header_invalid` | the protected header is not exactly `alg`, `kid` and `typ` in canonical form, names the wrong `typ` or an unknown `alg`, or names an `alg` the payload's `protocol_revision` does not allow | `Ed25519` in a revision-1 artifact, a header with extra members, a `kid` with characters outside `A-Z a-z 0-9 - . _ ~` | reject the input |
| `:signature_invalid` | the signature does not verify under the key it names, or its length is wrong for the algorithm | a tampered artifact, or a signature made with another key | reject the input |

## Party Descriptors

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:descriptor_invalid` | the descriptor's claims are inconsistent | a public key of the wrong length, an ML-DSA key in a revision-1 or revision-2 descriptor, duplicate key ids, no active key, a genesis with `party_id` or a successor without it | reject the input |
| `:descriptor_key_invalid` | the signing `kid` is not an active key where it must be | a genesis signed by a key it does not list, or a successor signed by a key that is not active in its predecessor | reject the input |
| `:descriptor_chain_invalid` | a descriptor history does not link up | no genesis or two, the same descriptor twice, a successor whose number, predecessor digest or `party_id` does not follow, or predecessor facts that do not verify again | reject the input; if you passed the predecessor facts, pass the ones `verify_descriptor` returned |

## Charter chain and governing revision

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:revision_invalid` | the revision's claims are inconsistent | a genesis with `charter_id`, `prev_revision_digest` or `supersedes`; a later revision without the first two; duplicate roles; one descriptor named for both parties; an ABP binding for a role that is not a party; an `effective_until` that does not follow `effective_from`; an unregistered `receipt_profile` | reject the input |
| `:acceptance_invalid` | the acceptance's claims are inconsistent, or its key is not active | revision 1 with a `prev_revision_digest`, a later revision without one, or a `kid` that is not an active key in the party's descriptor | reject the input |
| `:acceptance_claims_mismatch` | the acceptance does not match the revision it is checked against | another charter, revision number, digest or predecessor; a role or descriptor that is not one of the revision's parties | reject the input |
| `:acceptance_equivocation_invalid` | `Acceptance.equivocation/2` got two acceptances that are not one party accepting two revisions at one number | different parties or numbers, or the same revision twice | fix your call |
| `:termination_invalid` | the notice's claims are inconsistent, or its key is not active | `issued_at` after `effective_at`, or a `kid` that is not an active key | reject the input |
| `:termination_claims_mismatch` | the notice does not match the revision it names | another charter or revision, a `reason_code` the revision's `termination_rules` do not list, or a party that is not one of the revision's | reject the input |
| `:chain_invalid` | the artifacts do not form one charter view | no revisions or no descriptors; descriptors for other than two parties; revision parties that resolve to one party's descriptor history, or a history no revision names; zero or two genesis revisions; mixed charters; a broken predecessor or `supersedes` link; an acceptance or notice that names a revision or descriptor missing from the view; two acceptances by one party for one revision; an accepted revision that supersedes one that is not accepted | reject the input; if you assembled the view, check that it is complete |
| `:governing_invalid` | `governing_revision/2` got a `DateTime` that is not in UTC | a local-time `DateTime` | fix your call: convert the instant to UTC |

## Receipts

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:receipt_invalid` | the receipt's claims are inconsistent, or its context is unusable | a `bap`-scheme `grant` without `grant_digest`, `recorded_at` before `occurred_at`, or chain facts that did not come from `verify_chain` | reject the input; if the subject points at the context, pass facts from `verify_chain` |
| `:receipt_claims_mismatch` | the receipt does not match the revision it names | another charter, revision number or digest, a role that is not a party, or a `deployment_digest` that is not the revision's ABP binding for `agent_party_role` | reject the input |

## Extensions

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:extension_namespace_invalid` | an extension name is not a lowercase `owner/name` of at most 512 bytes | uppercase letters, spaces, a missing `/` | reject the input |
| `:extension_duplicate` | one name appears twice across `critical` and `optional` | the same extension in both lists | reject the input |
| `:extension_unknown_critical` | a critical extension this release does not know | an extension from a newer profile, or a private one marked critical | reject the input: an unknown critical extension cannot be skipped |
| `:extension_criticality_conflict` | a registered extension sits in the wrong list | a critical-only extension under `optional`, or the reverse | reject the input |
| `:extension_retired` | a critical extension the registry has retired | a producer still emitting a withdrawn extension | reject the input |
| `:extension_schema_unavailable` | a registered extension has no schema to check its body | an extension registered without a published schema | reject the input |
| `:extension_schema_digest_mismatch` | an extension schema does not match the digest the registry pins | a modified schema passed through `Extension.validate/3` | fix your call; the compiled registry always matches |
| `:extension_scope_invalid` | an extension sits on an artifact type it is not registered for | a receipt extension inside a revision | reject the input |

## Limits and profiles

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:invalid_limits` | the limits value is not valid | an unknown field, a negative value, or a value above the maximum | fix your call; build limits with `Limits.new/1` |
| `:invalid_profile` | the profile value is not valid | an unknown `alg` name, an empty or duplicated list, a revision range outside 1 to 3 or reversed | fix your call; build profiles with `Profile.new/1` |
| `:limit_exceeded` | the input is larger than a limit allows; the subject names which one | an oversized artifact, a deep JSON value, a chain view with too many artifacts or bytes | reject the input, or raise that limit if the input is legitimate |
| `:algorithm_outside_profile` | the artifact's `alg` is not in your profile | an ML-DSA artifact under an Ed25519-only profile | reject the input under your policy |
| `:revision_outside_profile` | the artifact's `protocol_revision` is outside your profile's range | a revision-1 artifact under `revisions: {2, 3}` | reject the input under your policy |

A profile code is returned before that artifact's signature is checked, so it never
says whether the signature is good.

## Runtime

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:algorithm_unsupported_on_substrate` | this runtime cannot check the artifact's signature algorithm; the checks before the signature check passed, and whether the signature is valid is unknown | an ML-DSA artifact on a runtime whose crypto library lacks ML-DSA, such as OTP linked against OpenSSL older than 3.5 | treat the artifact as unverified, not as invalid and not as verified (a forged signature of the right length gets this code too); verify it on a capable runtime |

This code depends on the runtime, not on the bytes, so two correct verifiers
on different runtimes can return different results for it. It is not part of
the conformance results. [Integrate CAP into an application](integration.md)
shows how to check the runtime at boot.

## Producing artifacts

The signing-input functions (`descriptor_signing_input/1`,
`acceptance_signing_input/2`, `termination_signing_input/2`,
`receipt_signing_input/1`) and `assemble_compact/2` return these.

| Code | Meaning | Typical cause | What to do |
|---|---|---|---|
| `:signing_input_invalid` | the input does not describe a valid artifact for this producer | claims that fail the artifact's schema, a `protocol_revision` that does not match the algorithm (`Ed25519` signs at 2, `ML-DSA-65` at 3), an unknown `"algorithm"`, a bad `kid`, extra input members | fix the claims |
| `:signing_refused` | the claims contradict the signer's own view of the charter | accepting a revision with wrong coordinates, accepting a sibling of a revision the party already accepted, an ancestry that leaves out an accepted head, a notice whose revision does not govern at `effective_at` or whose `reason_code` is not listed | do not sign; correct the claims or the view you passed |

`assemble_compact/2` returns `:signature_invalid` when the signature length is
wrong for the algorithm. It does not check that the signature belongs to the
right key, so verify each artifact after you assemble it.

## Conformance corpus

The corpus loader returns these when the conformance CLI reads a corpus
directory, or when `Conformance.Corpus.load/1` loads a map of corpus files.
The CLI prints `conformance verification failed` and exits with status 1.

| Code | Meaning | What to do |
|---|---|---|
| `:corpus_index_invalid` | `index.json` is malformed, or its corpus digest does not match | use the corpus shipped in the package, unedited |
| `:corpus_case_invalid` | a case file or case entry is malformed | same |
| `:corpus_hash_mismatch` | a file does not hash to the value the index records | same |
| `:corpus_file_set_mismatch` | the directory holds other files than the index lists | point the CLI at the corpus directory itself |
| `:corpus_case_id_duplicate` | two cases share an id | use the shipped corpus |
| `:corpus_count_mismatch` | the case counts differ from the index | use the shipped corpus |
| `:corpus_applicability_incomplete` | the corpus lacks a case class this release requires | use the corpus from the same release as the package |
| `:corpus_empty` | the index records no cases | use the shipped corpus |

## Appendix: how each code is exercised

Every code is produced either by a case in the conformance corpus
(`corpus-exercised`) or, where no corpus case can produce it, by the
library's own tests through the public API (`test-exercised`).

| Code | Exercised by | Why |
|---|---|---|
| `:acceptance_claims_mismatch` | corpus-exercised | a corpus case expects this code |
| `:acceptance_equivocation_invalid` | corpus-exercised | a corpus case expects this code |
| `:acceptance_invalid` | corpus-exercised | a corpus case expects this code |
| `:algorithm_outside_profile` | corpus-exercised | a corpus case expects this code |
| `:algorithm_unsupported_on_substrate` | test-exercised | depends on the runtime, not the bytes |
| `:base64url_invalid` | corpus-exercised | a corpus case expects this code |
| `:base64url_padded` | corpus-exercised | a corpus case expects this code |
| `:cardinality_violation` | corpus-exercised | a corpus case expects this code |
| `:chain_invalid` | corpus-exercised | a corpus case expects this code |
| `:compact_invalid` | corpus-exercised | a corpus case expects this code |
| `:constraint_violation` | corpus-exercised | a corpus case expects this code |
| `:corpus_applicability_incomplete` | test-exercised | fires while a corpus loads |
| `:corpus_case_id_duplicate` | test-exercised | fires while a corpus loads |
| `:corpus_case_invalid` | test-exercised | fires while a corpus loads |
| `:corpus_count_mismatch` | test-exercised | fires while a corpus loads |
| `:corpus_empty` | test-exercised | fires while a corpus loads |
| `:corpus_file_set_mismatch` | test-exercised | fires while a corpus loads |
| `:corpus_hash_mismatch` | test-exercised | fires while a corpus loads |
| `:corpus_index_invalid` | test-exercised | fires while a corpus loads |
| `:cross_field_invalid` | corpus-exercised | a corpus case expects this code |
| `:descriptor_chain_invalid` | corpus-exercised | a corpus case expects this code |
| `:descriptor_invalid` | corpus-exercised | a corpus case expects this code |
| `:descriptor_key_invalid` | corpus-exercised | a corpus case expects this code |
| `:digest_algorithm_unsupported` | corpus-exercised | a corpus case expects this code |
| `:digest_encoding_invalid` | corpus-exercised | a corpus case expects this code |
| `:digest_mismatch` | corpus-exercised | a corpus case expects this code |
| `:duplicate_member` | corpus-exercised | a corpus case expects this code |
| `:extension_criticality_conflict` | corpus-exercised | a corpus case expects this code |
| `:extension_duplicate` | corpus-exercised | a corpus case expects this code |
| `:extension_namespace_invalid` | corpus-exercised | a corpus case expects this code |
| `:extension_retired` | corpus-exercised | a corpus case expects this code |
| `:extension_schema_digest_mismatch` | test-exercised | needs a schema other than the compiled one |
| `:extension_schema_unavailable` | corpus-exercised | a corpus case expects this code |
| `:extension_scope_invalid` | corpus-exercised | a corpus case expects this code |
| `:extension_unknown_critical` | corpus-exercised | a corpus case expects this code |
| `:governing_invalid` | test-exercised | needs a non-UTC instant, which the runner does not pass |
| `:integer_magnitude` | corpus-exercised | a corpus case expects this code |
| `:invalid_encoding` | corpus-exercised | a corpus case expects this code |
| `:invalid_limits` | corpus-exercised | a corpus case expects this code |
| `:invalid_number` | corpus-exercised | a corpus case expects this code |
| `:invalid_profile` | test-exercised | needs a malformed profile, which the runner does not pass |
| `:invalid_syntax` | corpus-exercised | a corpus case expects this code |
| `:invalid_type` | corpus-exercised | a corpus case expects this code |
| `:limit_exceeded` | corpus-exercised | a corpus case expects this code |
| `:missing_required` | corpus-exercised | a corpus case expects this code |
| `:nested_invalid` | corpus-exercised | a corpus case expects this code |
| `:non_canonical_bytes` | corpus-exercised | a corpus case expects this code |
| `:number_not_double_expressible` | corpus-exercised | a corpus case expects this code |
| `:protected_header_invalid` | corpus-exercised | a corpus case expects this code |
| `:receipt_claims_mismatch` | corpus-exercised | a corpus case expects this code |
| `:receipt_invalid` | corpus-exercised | a corpus case expects this code |
| `:revision_invalid` | corpus-exercised | a corpus case expects this code |
| `:revision_outside_profile` | corpus-exercised | a corpus case expects this code |
| `:signature_invalid` | corpus-exercised | a corpus case expects this code |
| `:signing_input_invalid` | test-exercised | comes from the producer, which the runner does not call |
| `:signing_refused` | test-exercised | comes from the producer, which the runner does not call |
| `:termination_claims_mismatch` | corpus-exercised | a corpus case expects this code |
| `:termination_invalid` | corpus-exercised | a corpus case expects this code |
| `:timestamp_invalid` | corpus-exercised | a corpus case expects this code |
| `:trailing_bytes` | corpus-exercised | a corpus case expects this code |
| `:unknown_member` | corpus-exercised | a corpus case expects this code |
