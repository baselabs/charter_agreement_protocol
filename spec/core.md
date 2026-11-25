# Charter Agreement Protocol — core specification

Status: initial candidate. This document is the normative specification of the
Charter Agreement Protocol (CAP). The generated requirements matrix
(`requirements.md`) binds every requirement identifier cited here to its
certified evidence; the wire grammar schemas (`schemas/`) are the single
normative machine grammar; the guides under `../docs/guides/` explain how to
use and implement it.

## 1. Conformance language and requirement identifiers

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

Every normative statement below carries a stable requirement identifier of
the form `CAP-<SURFACE>-<kebab-tag>` in square brackets. An implementation
conforms to a requirement by satisfying its statement and by passing the
corpus, gate, and mutation evidence bound to it in the requirements matrix.
Uppercase normative keywords appear only on statements whose rejection
behavior carries certified corpus evidence; decode-layer rules whose
enforcement is codec-side and unit-proven are stated declaratively
without the keywords. Verdict-changing corrections to a published
revision follow the errata policy at `../docs/errata.md`: they name the
affected requirement identifiers and re-certify their evidence.

CAP reports evidence; it does not adjudicate, authorize, or decide legal
validity. No statement in this specification grants authority to any party
or host: verification produces structural facts only, and every fact record
carries an explicit floor of what was not verified
[CAP-FACTS-union-complete].

## 2. Encoding layer

### 2.1 JSON

CAP artifacts are JSON text [RFC8259]. A decoder MUST reject duplicate
object names, trailing non-whitespace content, invalid UTF-8, and inputs
above the caller-supplied byte ceiling, and MUST decode exactly one
complete value [CAP-JSON-decoder-closed-grammar]. A decoder MUST treat
numbers as ECMAScript doubles: an integer whose magnitude exceeds the
I-JSON safe range (2^53 − 1) MUST be rejected rather than silently
rounded [CAP-JSON-number-boundaries]. The byte ceiling boundary is exact:
an input at the ceiling accepts, one byte above rejects
[CAP-JSON-number-boundaries].

The decoder checks limits validity before input type, then the byte ceiling,
then parses from left to right. It reads enough syntax to begin a container
before checking that container's depth. Thus a lone `{` returns
`invalid_syntax` even with `max_depth: 0`; `[bad` reaches the array depth
check first and returns `limit_exceeded` at that limit. This is a streaming
check order, without a separate whole-document syntax pass. Invalid limits
with a non-text input return `invalid_limits`; valid limits with a non-text
input return `invalid_type` [CAP-JSON-check-order].

### 2.2 Canonical JSON

Signing and digesting operate on canonical JSON bytes (JCS-inspired,
I-JSON narrowed). An encoder MUST order object members by UTF-16 code unit,
MUST serialize numbers such that they round-trip as ECMAScript doubles —
a whole float MUST NOT collapse to an integer token where the decoded
value would differ — and MUST reject non-character code points
[CAP-CANONICALIZATION-ecmascript-number]. An encoder MUST reject member
order that is not canonical, bytes that are not minimal for their value,
and inputs of the wrong type, so that two implementations producing the
same decoded value also produce identical bytes
[CAP-CANONICALIZATION-noncanonical-rejected].

Every claims member typed as an integer by its schema requires an integer
token. A float token, including a whole-number token such as `1.0`, returns
`signing_input_invalid` during signing construction and the schema's
`invalid_type` code during verification or revision decoding, before
canonical spelling is checked. This includes nested integer members
[CAP-JSON-integer-claims].

### 2.3 base64url

Base64url encodings MUST be unpadded: a decoder MUST reject input
containing `=` padding [CAP-BASE64URL-unpadded-only]. The two-character
input boundary is exact: a two-character final group accepts, an invalid
character or a dangling single character rejects
[CAP-BASE64URL-exact-boundary].

### 2.4 Digests

Every digest is domain-separated: a digest computation MUST prefix the
input with the domain's registered separator so that identical content
under two domains yields different digests
[CAP-DIGEST-domain-separation]. Digest inputs MUST be bytes; a non-binary
input MUST be rejected rather than coerced
[CAP-DIGEST-bytes-only]. Digest comparison on a verification path MUST be
constant-time and MUST compare against the recomputed digest — a declared
digest that does not equal the recomputed value MUST fail verification
[CAP-DIGEST-equality-required]. A tagged digest is the 8-character prefix
`sha-256:` followed by exactly 43 base64url characters; its charset is
enforced by the codec (the schema layer bounds length only).

### 2.5 Timestamps

Instant-valued members are RFC 3339 [RFC3339] timestamps narrowed to
uppercase `T` and a `Z` offset, with optional fractional seconds and
leap-second syntax. A value outside that grammar fails decode; the
enforcement is codec-side (the schema layer bounds length only), and the
corpus exercises timestamps positively in every valid artifact. Timestamp
ordering uses a total order that preserves the leap-second slot. Every
timestamp-valued member — including the party descriptor's
`effective_from` — carries a 1..64 string-byte schema constraint
[CAP-DESCRIPTOR-timestamp-floor]: a codec-parseable spelling longer than
64 bytes is not a legal member value.

## 3. Schema layer

Every artifact claim set is a closed object: an unknown member MUST be
rejected [CAP-SCHEMA-closed-members]. A member of the wrong JSON type
MUST be rejected [CAP-SCHEMA-constraint-closed], as MUST a member that
violates its declared constraint (enumeration, range, length, or
cardinality) [CAP-SCHEMA-constraint-closed]. A value that satisfies its
declared schema decodes successfully
[CAP-SCHEMA-valid-decode]. Conditional member presence, cross-field
ordering, and paired-value rules are codec-enforced and are normative in
this document's artifact sections.

## 4. Artifacts

Four artifacts are attached compact JWS [RFC7515] whose signatures verify
under the algorithm their registry row names. The charter revision and
descriptor publication use canonical unsigned JSON. A verifier MUST verify each attached signature
over the exact compact signing-input bytes with the resolved public key
under the row's key algorithm — Ed25519 [RFC8032] or pure ML-DSA
(FIPS 204, context the empty string) [RFC9964]; a signature that does not
verify under that algorithm and key MUST fail
[CAP-SIGNATURE-ed25519-verification].

An Ed25519 public key and the signature `R` MUST each be exactly 32 bytes
[CAP-SIGNATURE-ed25519-verification]. Decode `y` as the
little-endian integer with the top bit cleared and use that bit as the sign
of `x`. With `p = 2^255 - 19` and `d = -121665/121666 mod p`, a verifier MUST
reject `y >= p`, reject when `(y^2 - 1)/(d*y^2 + 1) mod p` has no square
root, and reject `x = 0` with the sign bit set
[CAP-SIGNATURE-ed25519-verification]. Choose the root whose parity
matches the sign bit to obtain `P = (x, y)`. A verifier MUST reject when
`[8]P` is the identity [CAP-SIGNATURE-ed25519-verification]. Points of mixed order are admitted
[CAP-SIGNATURE-ed25519-verification].

Every attached artifact carries
`protocol_revision`; revisions 1, 2, 3, and 8 are defined (revision 1 closed
the `alg` name set to `EdDSA`; revision 2 admits the fully-specified
`Ed25519` name; revision 3 admits the ML-DSA names; revision 8 adds
key commitments and publication for party descriptors), and a decoder
encountering an unknown revision MUST fail closed
[CAP-REVISION-fail-closed].

### 4.1 Protected headers

A protected header MUST be closed to exactly `alg`, `kid`, and
`typ`; an unknown header member MUST be rejected
[CAP-COMPACT-JWS-type-isolation]. The `alg` value MUST be one of the
registered names, bound per artifact to the payload's `protocol_revision`
(the algorithm registry): `EdDSA` is accepted at any accepted revision,
`Ed25519` [RFC9864] is accepted from `protocol_revision` 2, and the three
fully-specified JOSE names `ML-DSA-44`, `ML-DSA-65`, and `ML-DSA-87`
[RFC9964] are accepted from `protocol_revision` 3, each verifying with a
key of its own parameterization whose public-key and signature byte
lengths are the registry row's exact values; a name below its row's
minimum revision MUST be rejected — no honest producer could have minted
the pair [CAP-ALG-registry-binding] [CAP-ALG-mldsa-registry-rows].
Outside revision-8 party descriptors, producers MUST mint exactly (`Ed25519`, `protocol_revision` 2) or
(`ML-DSA-65`, `protocol_revision` 3); accepting `EdDSA`
at revisions 2 and 3 keeps artifacts from producers that adopt a revision
before renaming their emission verifiable [CAP-ALG-registry-binding].

Every release reproduces the verdicts of every previously certified
conformance corpus except transitions this specification enumerates
[CAP-RELEASE-historical-certification].

A verifier MAY be supplied a capability profile narrowing the registry
names and `protocol_revision` values it admits, per artifact, applied
before any cryptographic work; an artifact outside the profile's name set
MUST be rejected as out of profile, and an artifact whose
`protocol_revision` is outside the profile's revision range MUST be
rejected as out of profile, on every substrate alike
[CAP-PROFILE-admission-axes]. A call that re-verifies caller-supplied
context MUST apply the same profile to every artifact in that context:
the supplied revision first, then the supplied descriptor history or
artifact set, then the artifact under verification; a revision-only
receipt context names no signing key, so the receipt's signature stays
unchecked, but its envelope is still admitted against the profile
[CAP-PROFILE-context-admission]. A profile never widens admission, and
verification under the full profile is exactly verification without one
[CAP-PROFILE-narrow-verification]. The `typ` value MUST be one of the four
registered artifact types (`cap+party`, `cap+acceptance`,
`cap+termination`, `cap+receipt`), and a verifier MUST NOT accept an
artifact whose `typ` differs from the expected type for the call
[CAP-COMPACT-JWS-type-isolation]. The `kid` member is a bounded-ASCII
lookup hint with no authority by itself; resolution against the declared
key history decides which key verifies.

### 4.2 Party Descriptor (`cap+party`)

A genesis descriptor (no `party_id`, no `prev_descriptor_digest`) that
satisfies its closed member set decodes and verifies as a self-standing
key history [CAP-PARTY-DESCRIPTOR-valid-genesis]. Descriptor claims MUST
satisfy the successor shape — a genesis carrying predecessor fields
rejects, the signing `kid` MUST resolve against a declared active key,
and instant members MUST parse [CAP-PARTY-DESCRIPTOR-decode-shape]. Every attached
descriptor MUST carry a verifiable signature from an active key
declared in the descriptor itself (genesis) or in its predecessor
(successors) — verified under the registry row's key algorithm; a signature that does not verify MUST be rejected
[CAP-PARTY-DESCRIPTOR-signature-required]. A successor MUST name its
exact predecessor by digest, and the lineage so named MUST re-verify —
predecessor lineage supplied as facts is re-verified, never trusted
[CAP-PARTY-DESCRIPTOR-predecessor-binding]. A descriptor superseded by a
later descriptor in its history MUST be reported with its position, not
silently accepted as current
[CAP-PARTY-DESCRIPTOR-superseded-visible]. The Ed25519 point rule in section
4 applies to both the public key and the signature `R` before signature
verification. An ML-DSA key or signature
whose byte length differs from its parameterization's registry row is
rejected before cryptographic work; the exact per-name lengths are
registry data [CAP-SIGNATURE-mldsa-lengths]. A descriptor at a
`protocol_revision` below 3 that declares an ML-DSA verification key MUST
be rejected — the key grammar is gated on the descriptor's revision
exactly as the `alg` name is [CAP-PARTY-DESCRIPTOR-key-grammar-gate].

#### 4.2.1 Successor key commitments

A party descriptor MAY include `next_key_commitment` at revision 8
[CAP-DESCRIPTOR-commitment-member]. At revisions 1 through 3 the decoder
MUST reject that member [CAP-DESCRIPTOR-commitment-member]. Producers of
revision-8 descriptors MUST emit `Ed25519` or `ML-DSA-65`
[CAP-DESCRIPTOR-commitment-emission].

A key thumbprint MUST hash a canonical object containing exactly `algorithm`
and `public_key` under the `signer_key` digest domain
[CAP-DESCRIPTOR-key-thumbprint]. The separator is
`charter-agreement-protocol/signer-key` followed by NUL. The `public_key`
is the key's canonical base64url encoding. Renaming a key leaves its
thumbprint unchanged.

At revision 8 active key thumbprints MUST be distinct
[CAP-DESCRIPTOR-distinct-key-material]. A commitment MUST hash the canonical
array of every active tagged thumbprint, sorted bytewise, under the
`descriptor_next_keys` digest domain [CAP-DESCRIPTOR-complete-key-set].
The separator is `charter-agreement-protocol/descriptor-next-keys`
followed by NUL. Retired keys remain subject to key grammar and are
excluded from this array.

After predecessor binding and profile admission, a successor of a committed
descriptor MUST carry revision 8 [CAP-DESCRIPTOR-opening-revision].
The verifier MUST compare the commitment to the successor's complete active
key set in constant time [CAP-DESCRIPTOR-complete-key-opening]. A failed
opening returns `descriptor_commitment_mismatch` in standalone verification
and `descriptor_chain_invalid` in a descriptor chain. The successor can
omit its own commitment. Valid competing openings remain fork evidence.

#### 4.2.2 Descriptor publication

An unsigned publication MUST be canonical JSON with exactly
`protocol_revision` equal to 8, `party_id`, `current_descriptor_digest`,
`next_descriptor_digest`, and `descriptors`
[CAP-PUBLICATION-closed-document]. The three digests MUST use canonical
tagged SHA-256 encoding [CAP-PUBLICATION-coordinate-grammar]. The
`descriptors` array MUST carry 2 to 4096 compact strings and satisfy
the caller's JSON and artifact-set ceilings [CAP-PUBLICATION-bounded-history].
The publication digest MUST hash the canonical publication bytes under
`descriptor_publication_content` [CAP-PUBLICATION-content-digest].
The separator is `charter-agreement-protocol/descriptor-publication-content`
followed by NUL.

The publication MUST supply the unique descriptors in a complete history
from genesis, sorted by descriptor number then digest
[CAP-PUBLICATION-history-order]. Every embedded descriptor and link MUST
verify under the caller's profile and limits [CAP-PUBLICATION-verify-history].
The document itself MUST satisfy the revision axis of the profile
[CAP-PUBLICATION-profile-revision]. The named party MUST match the genesis
digest of the history [CAP-PUBLICATION-party-binding]. The history MUST be
linear [CAP-PUBLICATION-linear-history]. The named next MUST be its sole head
[CAP-PUBLICATION-next-head]. The named current MUST be the direct predecessor
of next [CAP-PUBLICATION-direct-pair]. The parsed effective instant of next
MUST be strictly later than current's [CAP-PUBLICATION-effective-order].

Shape, canonical encoding, and publication relationship failures return
`descriptor_publication_invalid`. Embedded commitment, signature, profile
and substrate errors retain their codes. Publication facts retain the
canonical bytes, verified pair, coordinates, effective instants, and
whether the current descriptor's commitment opened or was absent. The
publication describes the supplied history. Hosts can combine multiple
publications to check for signed forks.

### 4.3 Charter Revision (unsigned canonical JSON)

A genesis revision (revision number 1, carrying no `charter_id`,
`prev_revision_digest`, or supersession targets) that satisfies its closed
member set decodes as the charter's founding document
[CAP-CHARTER-REVISION-valid-genesis]. The member set of a revision is
closed; an unknown member MUST be rejected
[CAP-CHARTER-REVISION-closed-members]. Each member MUST satisfy its
declared type and constraint — exactly two uniquely named party roles,
a non-empty unique reason-code set, a declared precedence, and typed
conditional members; a violation MUST be rejected
[CAP-CHARTER-REVISION-claim-constraints]. The genesis digest under the
`charter_revision_content` domain is the charter identity.

### 4.4 Acceptance (`cap+acceptance`)

An acceptance whose claims equal the revision's chain coordinates and
whose signer is a bound party verifies as a valid pairing
[CAP-ACCEPTANCE-valid-pairing]. The claims MUST match exactly — charter
identity, revision number, revision digest, predecessor digest when
present, party descriptor digest, and role; a mismatch MUST be rejected
[CAP-ACCEPTANCE-exact-claims]. A producer MUST refuse to mint an
acceptance signing input over a descriptor history whose branch state is
stale [CAP-SIGNING-branch-freshness]. Given two verified acceptances by
the same party descriptor and role at the same revision number over
different digests, a verifier MUST report the pair as equivocation
evidence and MUST NOT pick a winner
[CAP-ACCEPTANCE-equivocation-refusal]. A pair that is not same-signer,
same-number, same-role over different digests MUST be rejected as
unpairable evidence [CAP-ACCEPTANCE-EQUIVOCATION-pairing-required].

### 4.4.1 Pre-sign check

The pre-sign API accepts a kind, a closed map containing `kid`, `claims`,
raw `public_key` bytes and an optional emission `algorithm`, a context,
limits, and a profile. It returns a signing plan or a typed error. A plan
exposes the protected and payload segments, the exact signing message and
`key`; the public key, verified context, limits and profile are internal
fields that callers retain unchanged. Existing producer and assembly
arities retain their default limits and exact byte output.

The check MUST apply limits validation, profile validation, kind-specific
context typing, input construction, key shape, set verification and
producer refusals, verification preparation, snapshot membership, and
runtime support in that order [CAP-SIGNING-prepare-order]. Descriptor
context is absent or predecessor facts; acceptance and termination context
is an artifact set; receipt context is chain facts or a bare revision.

Input construction MUST frame, canonicalize, validate claims and decode a
zero-signature provisional compact under the caller's limits, including
the final signature segment size [CAP-SIGNING-caller-limits]. Limits MUST cover every artifact read in
the whole supplied set, and finishing MUST assemble under those same
limits [CAP-SIGNING-caller-limits]. Construction failures use
`signing_input_invalid`.

Key shape MUST use the registry's exact public-key length and, for
Ed25519, the strict point predicate shared with signature verification;
failure uses `signing_key_invalid` [CAP-SIGNING-key-shape].

The snapshot's kid, public bytes and artifact key algorithm MUST match an
active resolved candidate, or preparation returns `signing_key_mismatch`
[CAP-SIGNING-snapshot-membership].
Every resolved receipt candidate remains eligible, including two same-kid
keys. Only a bare-revision receipt skips membership and reports `unnamed`;
other successful plans report `matched` [CAP-SIGNING-snapshot-membership].
The candidates stay internal and describe the holder's own descriptor key
check.

Acceptance and termination preparation MUST verify the retained set, apply
the existing R1-R3 producer refusals, and derive the claimed revision and
signing party's descriptor chain using the same lookup as chain
verification [CAP-SIGNING-set-context]. A descriptor absent from every held chain returns
`acceptance_claims_mismatch` or `termination_claims_mismatch`
[CAP-SIGNING-set-context].

The retained set check for producer refusals MUST use the full profile
(every registered algorithm and revision)
[CAP-SIGNING-set-profile]. The caller's profile
MUST apply to the revision, signing party's descriptor history and artifact
for acceptance and termination, the whole retained set for a receipt, and
the predecessor history and artifact for a descriptor, exactly as in public
verification [CAP-SIGNING-set-profile].

Public verification and preparation MUST call the same internal
preparation step through candidate resolution, including context
re-verification, claims matching and profile admission
[CAP-SIGNING-shared-preparation].

Preparation MUST check declared support plus a known-answer verification
before returning a plan for every kind, including bare-revision receipts
[CAP-SIGNING-runtime-support].
That answer MUST be cached once per key algorithm
[CAP-SIGNING-runtime-support]. A raising provider call
is reported as unavailable; capability reporting returns normally
[CAP-SIGNING-runtime-support].

Finishing MUST assemble the external signature and invoke the public
artifact verifier with the CAP-derived context, plan limits and profile,
returning the compact only on success [CAP-SIGNING-finish-verification].

Malformed retained context field types MUST return `invalid_type` in public
verification and preparation [CAP-SIGNING-retained-input-totality]. Every field of caller-supplied chain facts,
descriptor chains, descriptor facts and revisions MUST be handled without
an exception [CAP-SIGNING-retained-input-totality]. Facts are reconstructed
from retained bytes, so supplied descriptive scalars do not replace the
verified values.

A companion signer accepting a caller-declared public key identity MUST
run CAP preparation for that identity before invoking any handle callback
[CAP-SIGNING-declared-key-preparation].
If preparation returns `signing_key_mismatch`, the signer MUST return a
refusal with that code and zero identity or signing calls
[CAP-SIGNING-declared-key-refusal]. Once preparation
succeeds, the signer MUST take one atomic handle identity snapshot and
refuse with the same code if it differs from the prepared identity
[CAP-SIGNING-declared-key-snapshot]. A
signature returned by custody still requires independent verification
against the prepared key [CAP-SIGNING-shared-preparation].

### 4.5 Termination Notice (`cap+termination`)

A termination notice pinned to a governing revision, a party descriptor,
and a listed reason verifies as a valid notice
[CAP-TERMINATION-valid-notice]. The reason code MUST be present in the
revision's termination declaration; an unlisted reason MUST be rejected
[CAP-TERMINATION-reason-closed]. The notice's effective and issued
instants MUST obey the declared ordering — `issued_at` after
`effective_at` rejects — under the same rejection class as an unlisted
reason [CAP-TERMINATION-reason-closed].

### 4.6 Receipt (`cap+receipt`)

Every receipt MUST carry a verifiable signature — under the registry
row's key algorithm — from an active
charter key of the issuing role; an unverifiable signature MUST be
rejected [CAP-RECEIPT-signature-required]. The receipt's revision number
MUST equal the number of the revision it names; a cross-number mismatch
MUST be rejected [CAP-RECEIPT-revision-number-match]. A receipt inside a
forked chain view MUST surface the conflict — the chain-conflict member
is evidence, never suppressed [CAP-RECEIPT-conflict-visible]. A receipt
whose signed outcome claim cannot be tied to an observed effect verifies
with outcome `indeterminate`; a verifier MUST NOT promote a signed claim
to an observed fact [CAP-RECEIPT-outcome-indeterminate]. Unknown optional
extension bodies MUST be retained byte-exactly through verification and
named as quarantined [CAP-RECEIPT-extension-roundtrip].

A chain-view receipt whose named revision is absent or lacks verified
acceptances from all parties MUST NOT report a governing match or a matched
deployment [CAP-RECEIPT-partial-view]. If the signature and charter and role claims
can be verified from the accepted revisions present, the receipt remains valid as
signed evidence. It reports `governing_match: mismatch` for a unique
different governing revision or none, and `undetermined` in a contested
view. It reports `chain_conflict: fork_evidenced` when the receipt's
revision number is at or below the highest accepted revision in the view.
An acceptance naming a missing revision invalidates the supplied view
with `chain_invalid` before receipt verification
[CAP-RECEIPT-conflict-visible].

### 4.7 Extension envelope

The extension envelope MUST be registry-conformant on every
envelope-bearing surface: a namespace of the wrong form, the same
namespace in both regions, a critical namespace that is unknown, reserved,
retired, declared optional, registered for another surface, or without a
bound schema MUST be rejected
[CAP-EXTENSION-envelope-closed]. A compact-JWS envelope MUST be
well-formed at the segment level — a malformed compact rejects
[CAP-COMPACT-JWS-envelope-well-formed].

## 5. Descriptor chains and artifact sets

A descriptor chain MUST verify every descriptor signature in the supplied
history; an unverifiable link invalidates the chain
[CAP-DESCRIPTOR-CHAIN-signature-required]. Chain topology is reported,
not adjudicated: a history with signed sibling forks reports a forked
topology with every contested position named.

A chain view MUST be bounded before any decode or signature check, with
each artifact list holding at most `max_artifact_set_items` items and the
byte lengths of all artifacts across the lists summing to at most
`max_artifact_set_bytes` [CAP-CHAIN-artifact-set-bounds]. A view exactly at
either ceiling verifies; one item or one byte above it rejects with
`limit_exceeded` [CAP-CHAIN-artifact-set-bounds].

## 6. Chain verification and governing revision

After validating limits, profile and list types, chain verification checks
artifact set bounds, verifies descriptors, then reads revisions, including
the nonempty revision check. With empty revisions, strict artifact set limits
can therefore return `limit_exceeded`, and a malformed descriptor can return
`compact_invalid`, before `chain_invalid`. Signing preparation uses the same
order when verifying an artifact set context after its earlier signing input
and key checks [CAP-CHAIN-check-order].

A set of revisions, acceptances, and descriptors whose acceptances pair
exactly and whose topology is linear verifies as a valid chain
[CAP-CHAIN-valid-topology]. A charter's parties MUST be distinct parties: a
revision MUST NOT name one descriptor for two roles, a revision's parties MUST
resolve to different descriptor histories, and every descriptor history in a
chain view MUST be one that a revision of the view names; any other view
rejects [CAP-CHAIN-distinct-parties]. A chain input MUST carry at least one
revision — an empty revision set rejects [CAP-CHAIN-input-nonempty]. A fork between accepted siblings MUST be
visible in the verified view — the forked topology and the sibling
digests are reported, never collapsed
[CAP-CHAIN-fork-topology]. A governing computation over a contested view
MUST return `contested`; a verifier MUST NOT resolve a tie by digest
ordering, freshness, or any other silent tie-break
[CAP-CHAIN-contested-refusal]. A supersession repair MUST be applied: a
later revision that supersedes contested siblings restores a unique
governing digest while history is retained
[CAP-CHAIN-supersession-applied]. A repair carrying only a
subset of the required party acceptances MUST leave the siblings contested
once both siblings are effective
[CAP-CHAIN-repair-acceptance]. Where a unique governing revision
exists, the revision with the highest precedence among eligible accepted
revisions MUST govern [CAP-CHAIN-highest-precedence], with eligibility
inclusive of the instant boundary. A verified termination notice that names
the revision governing at its `effective_at` MUST close the charter from
that instant: the governing computation at or after it returns `none`, and
a receipt for an effect at or after it does not match a governing revision
[CAP-CHAIN-termination-closes].
Comparisons MUST use UTC instants at their full represented precision
[CAP-CHAIN-termination-time-precision]. At equal instants, the verifier
MUST select the revision eligible at that instant before applying any
termination, then compare it to the notice's named revision
[CAP-CHAIN-termination-equal-instants]. A notice
naming a predecessor that has just lost precedence does not close the
charter. A notice naming the new governing revision closes it from that
instant, including queries and receipts at the same instant.

## 7. Facts and error surface

Verification results are redacted structural facts, never raw artifacts.
A facts record MUST carry the closed not-verified floor naming everything
the record does not prove, and additions to the floor MUST accumulate
without suppression [CAP-FACTS-union-complete]. Failures are typed and
value-free: error codes are closed and rejected input is never echoed
into an error, so verification failures are safe to log.

## 8. Conformance corpus

The certified conformance corpus binds every requirement's verdict to
executed cases: a runner MUST NOT report agreement for a case whose
projected output document differs from the certified expectation, and a
corpus whose declared expectations diverge from recomputed results fails
verification [CAP-CONFORMANCE-expectations-bound].

A corpus runner MUST return a typed outcome for every JSON input, including
malformed options and contexts [CAP-CONFORMANCE-runner-inputs]. A missing profile axis means the full axis;
an explicit null profile or axis is `invalid_profile`. It checks limits
before profile and profile before operation inputs. Case file readers MUST retain the distinction
between integer tokens and tokens with a fraction or exponent, including
whole-number floats such as `2.0` [CAP-CONFORMANCE-number-tokens].

The Elixir repository owns the canonical corpus. Consumers MUST pin an exact
source commit and the SHA-256 of the raw index bytes, check every case file
against its index digest, and compare the vendored bytes with the blobs at
that commit [CAP-CONFORMANCE-source-identity]. Full-capability
implementations MUST execute every row against `expect`
[CAP-CONFORMANCE-full-corpus]. A substrate without ML-DSA verification
MUST execute the same rows and use `expect_limited` where it is present
[CAP-CONFORMANCE-limited-corpus].
A capability diagnostic is distinct from a signature verdict.

## 9. Security and privacy posture

The threat model, the authorization boundary, and the data-exposure
analysis live in `security-considerations.md` and
`privacy-considerations.md`. In brief: signatures prove key-possession
statements, never real-world authority; equivocation and fork evidence is
retained, never adjudicated; and facts records are redacted so logs do
not expose retained signed artifacts.

## 10. References

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement
  Levels", BCP 14, RFC 2119, March 1997.
- [RFC8174] Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key
  Words", BCP 14, RFC 8174, May 2017.
- [RFC7515] Jones, M., Bradley, J., Sakimura, N., "JSON Web Signature
  (JWS)", RFC 7515, May 2015.
- [RFC8259] Bray, T., "The JavaScript Object Notation (JSON) Data
  Interchange Format", RFC 8259, December 2017.
- [RFC3339] Klyne, G. and C. Newman, "Date and Time on the Internet:
  Timestamps", RFC 3339, July 2002.
- [RFC8032] Josefsson, S. and I. Liusvaara, "Edwards-Curve Digital
  Signature Algorithm (EdDSA)", RFC 8032, January 2017.
- [RFC9864] "Fully-Specified Algorithms for JOSE and COSE", RFC 9864,
  October 2025.
- [RFC9964] "ML-DSA for JSON Object Signing and Encryption (JOSE) and
  CBOR Object Signing and Encryption (COSE)", RFC 9964, May 2026.
