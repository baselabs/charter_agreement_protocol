# Protocol foundation

This document defines the implemented byte-level, schema-validation, corpus,
Party Descriptor, and Charter Revision surfaces of Charter Agreement Protocol.
Acceptance and Termination Notice evidence verification is also implemented.
Governing-chain, Receipt verification, the external-signature signing seam, the
compiled extension registry, and the indexed-price profile are implemented.
Complete conformance reports are not part of the implemented surface yet.

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
| artifacts per set-level verification input | 1,024 | 4,096 |

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

## Party Descriptors

A Party Descriptor is an attached compact JWS with protected type
`cap+party`. Its protected header is closed to `alg`, `kid`, and `typ`; `alg`
must be `EdDSA`, `kid` uses the bounded ASCII protocol grammar, and the signature
is exactly 64 Ed25519 bytes. Protected-header and payload bytes must already be
canonical JSON. Before runtime signature verification, CAP rejects noncanonical
point encodings and all eight low-order torsion encodings for both the public
key and signature `R`. It also rejects signature scalars outside the canonical
subgroup-order range. The `kid` is only a lookup hint and has no authority by
itself.

The canonical payload contains exactly these claims:

- `protocol_revision`, fixed at the protocol data value `1`;
- conditional `party_id` and `prev_descriptor_digest` tagged digests;
- `descriptor_number`, beginning at 1 and increasing by exactly one;
- 1–32 unique Ed25519 verification keys, with at least one active key;
- 0–16 non-normative attestation hints, which this library never dereferences;
- a closed `extensions` envelope with `critical` and `optional` objects,
  validated against the compiled registry; and
- `effective_from`, in uppercase UTC RFC 3339 form ending in `Z`.

Genesis is self-signed by an active key declared in its own descriptor. Its
party identifier is the descriptor's domain-separated content digest. Every
successor names that identifier and the exact predecessor digest, increments
the descriptor number by one, and is signed by a key active in the predecessor.
Supplying predecessor facts does not bypass verification: their retained raw
lineage is reverified before it can authorize the next key transition.

`verify_descriptor_chain/2` accepts a complete in-view set in any order. A
single reachable history returns `:linear`; every non-head descriptor is marked
`:superseded`. Two or more individually valid descriptors naming the same
predecessor return `:forked`, mark all returned descriptor facts `:contested`,
and retain the sibling digests as signed fork evidence. The verifier never
selects a winner and never claims that the caller's view is globally complete.
The set size is bounded by `max_artifact_set_items`; the exact ceiling is
accepted and ceiling plus one returns `:limit_exceeded`.

Descriptor verification proves signed key continuity only. It does not prove
organizational identity, legal validity, authorization, current revocation
status, or ownership of an attestation target.

## Charter Revisions

A Charter Revision is unsigned canonical JSON. Its digest is computed over the
exact canonical bytes under the `charter_revision_content` domain. Genesis is
revision 1 and omits both `charter_id` and `prev_revision_digest`; every local
successor shape includes both. Genesis also carries no supersession targets,
because no prior-numbered revision can exist. Set-level continuity and
governance are separate verification surfaces.

Every revision contains exactly two uniquely named party roles bound to tagged
Party Descriptor digests. It declares legal text by a `legal_text` domain digest
over the raw legal bytes, media type, and optional URI hint. The precedence
declaration is mandatory and closed to `legal_text_governs` or
`machine_terms_govern`; no default is inferred. Effective timestamps are pure
UTC values, and an `effective_until` value must be later than `effective_from`.
Termination reason codes are non-empty, unique, and bounded.

ABP bindings preserve exact published Agent Blueprint Protocol identities:
party role, blueprint ID, positive release number, content digest, and deployment
digest. Decoding does not claim that the named deployment is available or
authorized. The frozen conformance vector comes from exact package 0.1.1 and
retains blueprint `example.demo/echo`, release 1, and both package-derived
digests without re-encoding them.

The extension envelope is closed to `critical` and `optional`. Registered
critical bodies must occupy their declared artifact surface and validate
against the exact schema digest compiled into the registry. Unknown critical
namespaces fail closed. Unknown optional bodies remain digest-covered and
byte-preserved in the decoded artifact but are quarantined; facts retain only
their namespaces. Unknown members, missing precedence, duplicate roles,
invalid cardinalities, malformed digests, widened identifiers, and
non-canonical bytes fail closed with value-free errors.

## Acceptances

An Acceptance is an attached compact JWS with protected type
`cap+acceptance`. Its eight closed claims bind the protocol revision, charter
identity, revision number and digest, conditional predecessor digest, Party
Descriptor digest and role, and a pure UTC `accepted_at` timestamp.

Verification re-decodes the retained revision bytes and reconstructs the signed
descriptor view from retained lineages. It requires exact equality with the
referenced revision's chain coordinates and exact membership in its party
bindings, resolves the protected `kid` only against a key active in the pinned
descriptor, and verifies Ed25519 over the attached JWS signing input. A pinned
descriptor may be head, superseded, or contested; that position is retained as
a fact and never converted into a freshness-policy decision.

Two individually verified acceptances from the same Party Descriptor and role
at one charter/revision number, but over different revision digests, produce
`AcceptanceEquivocation` evidence containing both signed content and revision
digests. The evidence has no winner. Acceptances by different parties on
competing branches are set-level contested-view evidence, not proof that one
signer equivocated.

Acceptance verification proves exact signed assent claims. It does not prove
legal validity, view completeness, current key revocation, authorization, or
term satisfaction.

## Termination Notices

A Termination Notice is an attached compact JWS with protected type
`cap+termination`. Its closed payload carries protocol revision, charter and
governing-revision digests, Party Descriptor digest and role, one reason code,
pure UTC `effective_at` and `issued_at` timestamps, and an optional opaque
`detail_digest`.

Verification re-decodes the retained Charter Revision and reconstructs the
signed descriptor view before use. The notice must bind the exact charter,
revision, party digest, and party role; its reason must be present in the
revision's termination declaration; `issued_at` may equal but may not follow
`effective_at`; and the protected `kid` must resolve to an active key in the
pinned descriptor before Ed25519 verification. The returned facts retain the
descriptor's view-relative position and never select a fresher branch.

The verifier reads no clock. A valid notice proves signed evidence only: it does
not prove delivery, receipt, legal effect, current revocation status, or that
the requested effective time has arrived. Governing-chain evaluation owns
those protocol-level effects.

## Chain verification and governing computation

`verify_chain/5` accepts complete caller-supplied lists of canonical revision
bytes, attached acceptances, Party Descriptor compacts, and termination
compacts plus explicit limits. It re-decodes and re-verifies every artifact;
raw routing claims never establish trust. Exactly two distinct descriptor
histories must match the revision's two bound roles. Revision digests must be
unique, one genesis must define the charter identity, every successor must bind
the exact prior-numbered digest, and supersession targets must exist within the
same charter and at a lower number.

A revision is accepted only when both bound Party Descriptor-and-role pairs
have one verified Acceptance. Signed same-number siblings remain fork evidence
and make the active view contested. An accepted successor may explicitly
supersede accepted lower-numbered branches; this retains historical fork and
equivocation evidence while removing the named branch residue from current
precedence. Digest ordering never selects a winner.

The returned `ChainFacts` are structural and view-relative. They contain the
reverified revision, acceptance, descriptor-chain, termination, supersession,
and fork facts, but no time-dependent verdict. `governing_revision/2` accepts a
caller-supplied UTC `DateTime` and returns the highest effective accepted
revision on one ancestry, `:contested` for multiple eligible branches, or
`:none`. Effective intervals are start-inclusive and end-exclusive.

A verified notice closes the charter at and after its `effective_at` only when
the notice names the unique governing revision at that instant. Closure never
reactivates an older revision. Neither verification function reads a clock,
performs authorization, or decides legal effect.

`build_set/4` only constructs a typed raw artifact set; it performs no
verification and its inspection is redacted. All facts records are built
through one shared constructor. It forces the closed twelve-item `not_verified`
floor: tenancy, live policy,
authority, effect ownership, execution, billing, evaluation truth, legal
validity, term satisfaction, view completeness, counterparty view, and wall
clock. Additional omissions are unioned and cannot replace that floor. Facts
implement redacted inspection so logs do not expose retained signed artifacts.

## Receipts

A Receipt is an attached compact JWS with protected type `cap+receipt`, signed
by the issuing party's charter key. Its closed payload contains the protocol and
charter identities, revision number and digest, issuing and agent party roles,
one exact ABP deployment digest, a typed grant reference, an invocation
identifier, decision and outcome, pure UTC occurrence and recording instants,
and the receipt-profile extension envelope.

The grant reference is `{scheme, id, grant_digest?}`. A BAP-scheme reference
requires the digest; a host-scheme reference may omit it. BAP `ath` is the
unpadded base64url SHA-256 of the complete received grant compact, while CAP
uses the tagged form, so exact composition is
`grant_digest = "sha-256:" <> ath`; decoding both yields the identical 32
digest bytes. The development/test gate recomputes this against exact Hex
package `bounded_authority_protocol` 0.1.2. It also decodes ABP's published
golden deployment with exact package `agent_blueprint_protocol` 0.1.1 and
requires CAP's frozen content and deployment digests to match the package's
recomputed output. Both dependencies are development/test-only and
runtime-disabled; production remains OTP-crypto-only.

`verify_receipt/3` enforces the four valid decision/outcome pairs: accepted may
report `effect_committed`, `no_effect`, or `indeterminate`; rejected requires
`no_effect`. `recorded_at` may equal but may not precede `occurred_at`. For a
recognized revision, charter identity, revision number, both party roles, and
the agent role's deployment binding must match exactly.

Full `ChainFacts` context is reverified from retained bytes before use. The
issuing role resolves to one active descriptor key, the Ed25519 signature must
verify, and governance is recomputed at `occurred_at`. An unrecognized revision
digest at or below the accepted head returns
`chain_conflict: :fork_evidenced`; no branch is selected. Governance comparison
is `:match`, `:mismatch`, or `:undetermined` when the view is contested.
Only bilaterally accepted revisions contribute recognized revision status,
role membership, or role-to-descriptor key resolution. A proposed revision is
unsigned data and cannot swap roles to promote a counterparty key.

The approved revision-only API form can prove structural revision/deployment
equality but has no descriptor key or chain view. Its facts therefore add
`:signature` to `not_verified`, set `signing_key_id` to `nil`, and report
governance as undetermined. Host post-sign verification uses full chain context.
Neither form validates live grant state, authorization, execution, effect truth,
legal validity, term satisfaction, view completeness, or wall-clock truth.

## Extensions and profiles

Every extension envelope is exactly
`{"critical": {namespace: body}, "optional": {namespace: body}}`. A namespace
is at most 512 UTF-8 bytes and has the lowercase reverse-DNS-plus-path form with
exactly one slash. An artifact may carry at most 32 namespaces total, and a
namespace may not occur in both regions.

`CharterAgreementProtocol.ExtensionRegistry` is compiled production data. Each
entry contains exactly `namespace`, `owner`, `criticality`, `state`,
`schema_digest`, `a2a_uri`, and `promoted_at_revision`. Registry changes are
package code releases; the runtime reads no registry file. Lifecycle states are
closed to reserved, active, deprecated, and retired. Retired names remain
occupied and cannot be reused. A critical body requires an active/deprecated
critical entry, the declared artifact placement, and a supplied schema whose
canonical schema-document digest equals the entry pin before validation.

Unknown critical and reserved-critical bodies are rejected. Unknown, reserved,
and retired optional bodies are retained exactly and quarantined. Registered
optional bodies must match criticality, placement, schema digest, and schema.
Neither a registry entry nor a successful extension verdict is authority.

All shipped identities use the RFC 2606 `example.com` reservation:
`com.example` reverse-DNS namespaces, `example.com` declaration URIs, and
example owners. The registry carries active indexed-price term and observation
profiles, the active schema-free core receipt profile, two reserved
attestation-family names, and one retired example namespace that mechanically
keeps retired-name reuse closed. The attestation entries define no bytes and
CAP does not interpret their bodies.

Profiles may define revision term schemas, receipt-extension members, and
evaluation-semantics documents. They cannot define signature, acceptance,
precedence, or authority semantics because those surfaces remain closed core
members outside extension bodies. The implemented price profile is specified
in [Indexed-price profile](profiles/indexed-price.md). Its revision terms and
receipt observations use separate namespaces because registry criticality is a
stable namespace property. CAP validates and binds the data but leaves
`term_satisfaction` in the facts omission floor; hosts independently compute
and compare prices.

## Signing inputs and compact assembly

Each producer accepts exactly `%{"kid" => kid, "claims" => claims}`. CAP builds
the closed `{alg: "EdDSA", typ, kid}` protected header and returns
`%SigningInput{kind, protected_segment, payload_segment, message}` where
`message` is the exact RFC 7515 signing input. Descriptor and Receipt producers
take only that map. Acceptance and Termination producers also take the caller's
raw `ArtifactSet` and cold-verify it before returning bytes.

The set-aware producers refuse false revision and party coordinates and preserve
the Artifact Set verifier's typed failures. The Acceptance producer refuses a
charter number already occupied by an acceptance for another digest and refuses
a candidate whose ancestry excludes any maximum dual-accepted head. A repair
revision may cover accepted siblings by naming each in `supersedes`; this is the
only no-tie-break path that lets the honest-signer seam construct fork repair.
Incomplete ancestry fails closed. The Termination producer instead requires its
named revision to be the unique governing revision at the notice's own
`effective_at`; it does not read a clock, and a later accepted revision whose
window has not started does not displace the current governing revision.

Claims accept the same JSON data model as canonicalization, including finite
floating-point extension values. The artifact codec remains the final closed
schema and semantic validator.

`assemble_compact/2` revalidates the kind/header/payload/message relationship and
accepts exactly one externally produced raw 64-byte Ed25519 signature. The
production package has no signing call, private-key parameter, signer callback,
signer module, or custody handle. Hosts own an atomic kid/key snapshot and must
post-verify the assembled compact through CAP before returning it. The refusal
guards constrain honest use relative to the supplied set; they cannot constrain
a dishonest signer or prove the view complete.

## Architecture boundaries

Production runtime code uses only OTP `:crypto`. Corpus loading is in-memory and
does not read files. All Mix dependencies are development/test-only and
`runtime: false`. The build rejects host, transport, database,
private-authority-runtime, and application-callback coupling.

The compiled-production battery rejects filesystem, calendar, wall-clock,
shell/OS-escape, and dynamic-dispatch calls. Source gates reject
authorization-decision and term-evaluation vocabulary, require every explicit
module to state its non-authorizing boundary, and require a specification for
every public function, macro, and delegate. Every facts struct is constructed
through the single shared omission-floor constructor. Exact source censuses
pin CAP's domain separators and protected types and prove they remain disjoint
from the consumed ABP and BAP package identities.

Protocol evolution is carried as digest-covered data. Version tokens are rejected
from durable paths and identifiers; the exact Hex package `source_ref` is the only
allowlisted identity.
