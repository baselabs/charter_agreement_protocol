# Charter Agreement Protocol — core specification

Status: initial candidate. This document is the normative specification of the
Charter Agreement Protocol (CAP). The generated requirements matrix
(`requirements.md`) binds every requirement identifier cited here to its
certified evidence; the wire grammar schemas (`schemas/`) are the single
normative machine grammar; the implementation guide lives at
`../docs/protocol.md`.

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
ordering uses a total order that preserves the leap-second slot.

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

Four artifacts are attached compact JWS [RFC7515] with Ed25519
signatures; the charter revision is canonical unsigned JSON. A verifier
MUST verify each attached signature as Ed25519 [RFC8032] over the exact
compact signing-input bytes with the resolved public key; a signature
that does not verify under that algorithm and key MUST fail
[CAP-SIGNATURE-ed25519-verification]. Every attached artifact carries
`protocol_revision` with the value `1`.

### 4.1 Protected headers

A protected header MUST be closed to exactly `alg` (`EdDSA`), `kid`, and
`typ`; an unknown header member MUST be rejected
[CAP-COMPACT-JWS-type-isolation]. The `typ` value MUST be one of the four
registered artifact types (`cap+party`, `cap+acceptance`,
`cap+termination`, `cap+receipt`), and a verifier MUST NOT accept an
artifact whose `typ` differs from the expected type for the call
[CAP-COMPACT-JWS-type-isolation]. The `kid` member is a bounded-ASCII
lookup hint with no authority by itself; resolution against the declared
key history decides which key verifies.

### 4.2 Party Descriptor (`cap+party`)

A genesis descriptor (no `party_id`, no `prev_descriptor_digest`) that
satisfies its closed member set decodes and verifies as a self-standing
key history [CAP-PARTY-DESCRIPTOR-valid-genesis]. Every attached
descriptor MUST carry a verifiable Ed25519 signature from an active key
declared in the descriptor itself (genesis) or in its predecessor
(successors); a signature that does not verify MUST be rejected
[CAP-PARTY-DESCRIPTOR-signature-required]. A successor MUST name its
exact predecessor by digest, and the lineage so named MUST re-verify —
predecessor lineage supplied as facts is re-verified, never trusted
[CAP-PARTY-DESCRIPTOR-predecessor-binding]. A descriptor superseded by a
later descriptor in its history MUST be reported with its position, not
silently accepted as current
[CAP-PARTY-DESCRIPTOR-superseded-visible]. Before signature verification,
non-canonical point encodings and all eight low-order torsion encodings
are rejected for both the public key and the signature `R`; this decode
layer rule is codec-enforced and unit-proven.

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
[CAP-ACCEPTANCE-equivocation-refusal].

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

Every receipt MUST carry a verifiable Ed25519 signature from an active
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

## 5. Descriptor chains and artifact sets

A descriptor chain MUST verify every descriptor signature in the supplied
history; an unverifiable link invalidates the chain
[CAP-DESCRIPTOR-CHAIN-signature-required]. Chain topology is reported,
not adjudicated: a history with signed sibling forks reports a forked
topology with every contested position named.

## 6. Chain verification and governing revision

A set of revisions, acceptances, and descriptors whose acceptances pair
exactly and whose topology is linear verifies as a valid chain
[CAP-CHAIN-valid-topology]. A fork between accepted siblings MUST be
visible in the verified view — the forked topology and the sibling
digests are reported, never collapsed
[CAP-CHAIN-fork-topology]. A governing computation over a contested view
MUST return `contested`; a verifier MUST NOT resolve a tie by digest
ordering, freshness, or any other silent tie-break
[CAP-CHAIN-contested-refusal]. A supersession repair MUST be applied: a
later revision that supersedes contested siblings restores a unique
governing digest while history is retained
[CAP-CHAIN-supersession-applied]. Where a unique governing revision
exists, the revision with the highest precedence among eligible accepted
revisions MUST govern [CAP-CHAIN-highest-precedence], with eligibility
inclusive of the instant boundary.

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
