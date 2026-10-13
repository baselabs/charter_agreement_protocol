# Artifacts and claims

CAP has five artifacts. Four are signed, as attached compact JWS (RFC 7515). The
charter revision is unsigned canonical JSON. This page lists every member of each
artifact and the main rules on it.

The normative grammar is the JSON Schema set in [`spec/schemas`](../../spec/schemas/README.md),
together with the rules in the [core specification](../../spec/core.md) that a schema
cannot express (character sets, conditional members, cross-field order). If this page
and those files disagree, the files win.

Every member set is closed: an unknown member fails with `unknown_member`. All bytes,
headers and payloads alike, must already be [canonical JSON](implementing.md#canonical-json).

## Signed artifacts

### Protected header

| Member | Rule |
|---|---|
| `alg` | One of the registry names below, allowed only from its minimum `protocol_revision` |
| `kid` | 1 to 128 bytes of `A-Z a-z 0-9 - . _ ~`. A lookup hint only: the signer's descriptor decides which key verifies |
| `typ` | `cap+party`, `cap+acceptance`, `cap+termination` or `cap+receipt`, and it must match the call |

| `alg` | Key algorithm | From `protocol_revision` | Public key bytes | Signature bytes |
|---|---|---|---:|---:|
| `EdDSA` | Ed25519 | 1 | 32 | 64 |
| `Ed25519` | Ed25519 | 2 | 32 | 64 |
| `ML-DSA-44` | ML-DSA-44 | 3 | 1,312 | 2,420 |
| `ML-DSA-65` | ML-DSA-65 | 3 | 1,952 | 3,309 |
| `ML-DSA-87` | ML-DSA-87 | 3 | 2,592 | 4,627 |

A verifier accepts all five names. A producer mints only two pairs: `Ed25519` at
`protocol_revision` 2, which is the default, and `ML-DSA-65` at `protocol_revision` 3.
The claims you pass to a producer must already carry the matching `protocol_revision`;
claims at revision 1 are refused with `signing_input_invalid`. The signature you hand
to `assemble_compact/2` is therefore 64 bytes (Ed25519) or 3,309 bytes (ML-DSA-65).
[Produce and verify with the signer](produce-and-verify.md) walks through it.

Key and signature bytes are checked against the row's exact lengths and encodings
before any signature work ([core specification](../../spec/core.md), section 4.2).

### Party descriptor (`cap+party`)

One party's keys and their history. The first descriptor (the genesis) is signed by a
key it declares itself. The digest of the genesis is the party's id. Each later
descriptor names the party id and its predecessor, has the next number, and is signed
by a key that was active in the predecessor.

| Member | Required | Rule |
|---|---|---|
| `protocol_revision` | yes | 1 to 3 |
| `party_id` | successors only | Tagged digest: the genesis descriptor's digest |
| `prev_descriptor_digest` | successors only | Tagged digest of the predecessor |
| `descriptor_number` | yes | 1 at genesis, then exactly one more each time |
| `verification_keys` | yes | 1 to 32 keys, unique, at least one `active`. Each key has `key_id`, `algorithm` (`Ed25519`, `ML-DSA-44`, `ML-DSA-65` or `ML-DSA-87`), `public_key` (base64url at the algorithm's exact length) and `status` (`active` or `retired`). ML-DSA keys need `protocol_revision` 3. One descriptor may mix algorithms |
| `attestation_hints` | yes | 0 to 16 hints, each `kind` and `uri`. CAP never fetches them |
| `extensions` | yes | The [extension envelope](#extension-envelope) |
| `effective_from` | yes | [Timestamp](implementing.md#timestamps) |

Verifying a descriptor proves signed key continuity. It does not prove who the party
is, or that a key has not been revoked since.

### Acceptance (`cap+acceptance`)

One party's signed assent to one exact revision. A revision counts as accepted when
each party it binds has a verified acceptance of it. Every revision binds exactly two
parties, so it needs two acceptances.

| Member | Required | Rule |
|---|---|---|
| `protocol_revision` | yes | 1 to 3 |
| `charter_id` | yes | The charter id. For the first revision, its own digest |
| `revision_number` | yes | The revision's number |
| `revision_digest` | yes | The revision's digest |
| `prev_revision_digest` | when the revision has one | Must equal the revision's `prev_revision_digest` |
| `party_descriptor_digest` | yes | The signer's descriptor, which the revision must bind |
| `party_role` | yes | The role that descriptor holds in the revision |
| `accepted_at` | yes | Timestamp |

Every coordinate must match the revision exactly, and `kid` must resolve to a key
active in the named descriptor. Two verified acceptances by the same descriptor and
role at the same revision number, over different digests, are reported as
equivocation evidence. CAP picks no winner.

### Termination notice (`cap+termination`)

One party's signed notice to end the charter at a stated instant.

| Member | Required | Rule |
|---|---|---|
| `protocol_revision` | yes | 1 to 3 |
| `charter_id` | yes | The charter id |
| `governing_revision_digest` | yes | The revision the notice names |
| `party_descriptor_digest` | yes | The signer's descriptor, bound by that revision |
| `party_role` | yes | The signer's role in that revision |
| `reason_code` | yes | Must be one of the revision's `termination_rules.reason_codes` |
| `effective_at` | yes | Timestamp |
| `issued_at` | yes | Timestamp, equal to or before `effective_at` |
| `detail_digest` | no | Tagged digest of detail kept elsewhere. CAP does not read it |

A verified notice closes the charter only when the revision it names is the one
governing at its `effective_at`. From that instant on, `governing_revision/2` returns
`:none`. A notice that names any other revision closes nothing. See
[Verification semantics](verification.md).

### Receipt (`cap+receipt`)

Signed evidence of one action, bound to the revision that governed it. The issuing
party signs it.

| Member | Required | Rule |
|---|---|---|
| `protocol_revision` | yes | 1 to 3 |
| `charter_id` | yes | The charter id |
| `revision_number` | yes | Must equal the named revision's number |
| `revision_digest` | yes | The revision the action ran under |
| `issuing_party_role` | yes | The role that signs |
| `agent_party_role` | yes | The role whose deployment acted. May be the same role |
| `deployment_digest` | yes | Must match that role's binding in the revision |
| `grant` | yes | `scheme` (`bap` or `host`), `id`, and `grant_digest` (required for `bap`) |
| `invocation_id` | yes | 1 to 512 bytes |
| `decision` | yes | `accepted` or `rejected` |
| `outcome` | yes | `effect_committed`, `no_effect` or `indeterminate`. `rejected` allows only `no_effect` |
| `occurred_at` | yes | Timestamp |
| `recorded_at` | yes | Timestamp, equal to or after `occurred_at` |
| `extensions` | yes | The extension envelope, including the receipt profile |

[Receipts](receipts.md) covers verification against a chain and the sibling protocols.

## Charter revision (unsigned)

One version of the terms. Its digest is SHA-256 over its exact canonical bytes under
the `charter_revision_content` domain. The first revision's digest is the charter id.

| Member | Required | Rule |
|---|---|---|
| `protocol_revision` | yes | 1 or 2 |
| `revision_number` | yes | 1 for the first revision, then exactly one more each time |
| `charter_id` | after the first | The charter id |
| `prev_revision_digest` | after the first | Digest of the revision numbered one lower |
| `supersedes` | no | 0 to 8 digests of lower-numbered accepted revisions in the same charter. Never on the first revision |
| `parties` | yes | Exactly two bindings, each `role` (unique) and `party_descriptor_digest` |
| `legal_text` | yes | `content_digest` (the raw legal text under the `legal_text` domain), `media_type`, optional `uri_hint` |
| `precedence_declaration` | yes | `legal_text_governs` or `machine_terms_govern`. Never assumed |
| `attribution_declaration` | yes | `basis` (`bound_deployments` or `legal_text`), optional `detail_digest` |
| `effective_from` | yes | Timestamp |
| `effective_until` | no | Timestamp, later than `effective_from` |
| `termination_rules` | yes | `reason_codes`: 1 to 64 unique codes |
| `abp_bindings` | yes | 0 to 64 deployment bindings, each `party_role`, `blueprint_id`, `release_number`, `content_digest`, `deployment_digest` |
| `receipt_profile` | yes | The namespace of the receipt profile receipts under this revision use |
| `extensions` | yes | The extension envelope |

The revision is unsigned, so it is the acceptances that make it binding. Use
`encode_charter_revision/1` to build revision bytes from a plain claims map: it
returns bytes only when they decode as a valid revision.

## Extension envelope

Party descriptors, charter revisions and receipts carry an `extensions` member.
Acceptances and termination notices have none.

```json
{"critical": {"<namespace>": {}}, "optional": {"<namespace>": {}}}
```

- A namespace is lowercase reverse DNS plus one path segment, such as
  `com.example/pricing-indexed`, at most 512 bytes.
- At most 32 namespaces per artifact, and a namespace appears in one region only.
- A critical body must be registered for that artifact and must match its registered
  schema. An unknown critical namespace fails.
- An unknown optional body is kept byte for byte and reported as quarantined.

[Extensions and profiles](extensions.md) covers the registry and the published
profiles.

## Facts

Verification returns facts, not the artifacts themselves: redacted records of what was
checked. Every facts record carries a `not_verified` list naming what CAP did not
check, such as legal validity and the wall clock. Facts print redacted, so they are
safe to log. [Verification semantics](verification.md) describes each facts record.
