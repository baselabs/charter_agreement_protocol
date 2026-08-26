# Artifacts

CAP has five artifact types. Four are attached compact JWS (RFC 7515) with
Ed25519 signatures; one is canonical unsigned JSON. Every signed artifact's
protected header is closed to exactly `alg` (`EdDSA`), `kid` (a bounded-ASCII
lookup hint with no authority by itself), and `typ`. Every artifact carries
`protocol_revision` as a digest-covered member. All bytes — headers and
payloads — must already be canonical JSON.

The public API entry points for each artifact live on
`CharterAgreementProtocol`; the member tables below are the normative closed
sets (see [Protocol foundation](../protocol.md) for the full contract).

## Party Descriptor — `cap+party`

A party's declared Ed25519 key history. Genesis is self-signed by an active key
declared in the descriptor itself; the party's identifier is the descriptor's
domain-separated content digest.

| Member | Contract |
|---|---|
| `protocol_revision` | fixed protocol data value `1` |
| `party_id` | conditional; tagged digest, present on successors |
| `prev_descriptor_digest` | conditional; exact predecessor digest, present on successors |
| `descriptor_number` | starts at 1, increases by exactly one |
| `verification_keys` | 1–32 unique Ed25519 keys, each with `key_id`, `algorithm`, base64url `public_key`, `status`; at least one `active` |
| `attestation_hints` | 0–16 non-normative hints; never dereferenced |
| `extensions` | closed envelope, registry-validated |
| `effective_from` | uppercase UTC RFC 3339 ending in `Z` |

A successor is signed by a key active in its predecessor; predecessor lineage
supplied as facts is reverified, never trusted. Before runtime signature
verification, CAP rejects noncanonical point encodings and all eight low-order
torsion encodings for both the public key and the signature `R`.

## Charter Revision — unsigned canonical JSON

The agreed terms. Its digest is computed over the exact canonical bytes under
the `charter_revision_content` domain. Genesis is revision 1 and carries no
`charter_id`, `prev_revision_digest`, or supersession targets.

| Member | Contract |
|---|---|
| `protocol_revision` | protocol data value `1` |
| `revision_number` | 1 at genesis, exactly one more per successor |
| `charter_id` | conditional; the genesis revision's digest on successors |
| `prev_revision_digest` | conditional; exact prior-numbered revision digest |
| `supersedes` | conditional; lower-numbered accepted revisions in the same charter |
| `parties` | exactly two uniquely named roles bound to tagged descriptor digests |
| `legal_text` | `content_digest` (raw legal bytes under the `legal_text` domain), `media_type`, optional `uri_hint` |
| `precedence_declaration` | exactly `legal_text_governs` or `machine_terms_govern`; never defaulted |
| `effective_from` / `effective_until` | pure UTC; `until` strictly later than `from` |
| `attribution_declaration` | closed attribution basis |
| `termination_rules` | non-empty unique bounded `reason_codes` |
| `abp_bindings` | exact published ABP identities per party role |
| `receipt_profile` | the receipt extension profile namespace |
| `extensions` | closed envelope, registry-validated |

## Acceptance — `cap+acceptance`

One party's signed assent to one exact revision. Eight closed claims:

`protocol_revision`, `charter_id`, `revision_number`, `revision_digest`,
conditional `prev_revision_digest`, `party_descriptor_digest`, `party_role`,
`accepted_at` (pure UTC).

Verification reconstructs the signed descriptor view from retained lineages and
requires exact equality with the revision's chain coordinates and exact
membership in its party bindings.

## Termination Notice — `cap+termination`

A pinned party's signed notice. Closed payload: `protocol_revision`,
`charter_id`, `governing_revision_digest`, `party_descriptor_digest`,
`party_role`, one `reason_code`, `effective_at`, `issued_at` (may equal, never
after, `effective_at`), and optional opaque `detail_digest`. The reason must be
present in the revision's termination declaration; the `kid` must resolve to an
active key in the pinned descriptor.

## Receipt — `cap+receipt`

Signed action evidence binding an invocation to the agreement that governed it.
See [Receipts](receipts.md) for the full contract including grant references
and decision/outcome pairs.

## Extension envelope (all artifacts)

Exactly `{"critical": {namespace: body}, "optional": {namespace: body}}`. A
namespace is at most 512 UTF-8 bytes in lowercase reverse-DNS-plus-path form
with exactly one slash; at most 32 namespaces per artifact; a namespace never
appears in both regions. Registered critical bodies validate against the exact
schema digest compiled into the registry; unknown critical namespaces fail
closed; unknown optional bodies are retained byte-exactly and quarantined. See
[Extensions and profiles](extensions.md).

## Facts records

Verification never returns raw artifacts as results — it returns *facts*:
redacted structural records (descriptor, acceptance, termination, revision,
chain, receipt facts). Facts implement redacted inspection so logs never expose
retained signed artifacts, and every facts record is built through one shared
constructor that forces the closed twelve-item `not_verified` floor. See
[Security model](security-model.md).
