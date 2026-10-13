# Extensions and profiles

An extension lets an artifact carry extra, schema-checked data without changing CAP's
closed member sets. A profile is a registered family of extensions with its own
schema and a document that says how hosts evaluate it. CAP checks the shape and binds
the bytes. It never acts on what an extension says, and a body that validates is still
only data.

"Profile" also names `Capability.Profile`, which narrows the algorithms and protocol
revisions you accept. That is a different thing; see
[limits and profiles](limits-and-profiles.md).

## Where extensions can appear

Three artifacts carry an extension envelope: the party descriptor, the charter revision
and the receipt. Acceptances and termination notices have closed claim sets with no
envelope.

The envelope is an object with exactly two members, both required: `critical` and
`optional`. Each maps namespaces to bodies, so an envelope with no extensions is
`{"critical":{},"optional":{}}`.

- A namespace is lowercase, in reverse-DNS form followed by one slash and a path, such
  as `com.example/pricing-indexed`, and at most 512 bytes.
- An artifact carries at most 32 namespaces across both regions.
- A namespace may not appear in both regions.

The two regions tell a verifier what to do with a namespace it does not know. A
`critical` namespace must be understood, or the artifact is rejected. An `optional`
namespace can be kept without being understood.

## The compiled registry

`CharterAgreementProtocol.ExtensionRegistry` is compiled into the package. CAP reads no
registry file at runtime, so a registry change is a new package release. Each entry has
exactly seven fields: `namespace`, `owner`, `criticality`, `state`, `schema_digest`,
`a2a_uri` and `promoted_at_revision`. Each entry is also assigned to one artifact
surface.

The `state` is one of `reserved`, `active`, `deprecated` or `retired`. A retired name
stays in the registry and is never reused, so a namespace always means the same thing.

## What happens to a body

| Body | In `critical` | In `optional` |
|---|---|---|
| Registered, active or deprecated | validated against the schema whose digest the registry pins | validated the same way |
| Registered with the other criticality | `:extension_criticality_conflict` | `:extension_criticality_conflict` |
| Registered for another artifact | `:extension_scope_invalid` | `:extension_scope_invalid` |
| Registered with no schema | `:extension_schema_unavailable` | `:extension_schema_unavailable` |
| Unknown or reserved | `:extension_unknown_critical` | kept and quarantined |
| Retired | `:extension_retired` | kept and quarantined |

Before validating a registered body, CAP checks that the schema it holds has the
canonical digest the registry pins. A different schema, even an equivalent one, fails
with `:extension_schema_digest_mismatch`. The envelope rules themselves fail with
`:extension_namespace_invalid` (bad namespace form), `:extension_duplicate` (a
namespace in both regions) or `:cardinality_violation` (more than 32).

## Quarantine

When a counterparty sends an optional namespace your release of CAP does not know,
verification still succeeds. The body stays byte for byte in the artifact, so the
signature and digest still cover it. The facts name it in
`optional_extensions_retained`, and CAP gives the body no meaning.

Your application decides what to do with optional evidence it does not understand.
CAP neither drops the bytes nor gives them a meaning. The corpus case
`receipt-indexed-price-observation-quarantine` shows a receipt with one known and one
unknown optional namespace: both are retained and both are listed.

## What ships in the registry

Every shipped namespace is an example under `example.com`, the domain RFC 2606
reserves for documentation. The owners and declaration URIs are examples too, and CAP
never fetches the URIs.

| Namespace | State | Criticality | Artifact |
|---|---|---|---|
| `com.example/pricing-indexed` | active | critical | charter revision |
| `com.example/pricing-indexed-observation` | active | optional | receipt |
| `com.example.charter/default` | active | optional | receipt |
| `com.example/identity-vlei` | reserved | optional | party descriptor |
| `com.example/identity-eidas-qeaa` | reserved | optional | party descriptor |
| `com.example/retired-profile` | retired | critical | charter revision |

- The two pricing namespaces form the indexed-price profile, described below.
- `com.example.charter/default` is the schema-free core receipt profile. A revision
  names the profile its receipts use in its `receipt_profile` member, and it must be a
  registered receipt profile.
- The two reserved names hold space for attestation profiles. They define no bytes,
  and CAP does not interpret bodies under them.
- The retired name exists so that the rule "a retired name is never reused" has a
  case that tests it.

## The indexed-price profile

The example pricing profile carries portable pricing terms in a revision (currency,
base amount, index reference, the `index_plus_spread` formula, spread, optional floor
and cap, tolerance) and the observed values in a receipt. The
[indexed-price profile](../profiles/indexed-price.md) lists every member.

The terms and the observations use two namespaces because criticality belongs to a
namespace, not to a use of it. Terms in a revision must be understood, so they are
critical. Observations in a receipt can be kept without being understood, so they are
optional.

CAP checks and binds the data. `term_satisfaction` stays in every facts record's
`not_verified` list. Each host gets the index value itself, computes the amount, and
applies its own policy.

## What a profile can and cannot define

A profile can define revision term schemas, receipt extension members and a document
describing how hosts evaluate them. It cannot change how signatures, acceptances or
precedence work. Those are closed core members outside any extension body, so no
extension can weaken verification.

Changing an agreed formula takes a new charter revision that both parties accept.
