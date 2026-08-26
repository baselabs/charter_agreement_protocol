# Extensions and profiles

Extensions carry portable, schema-validated data inside artifacts without
opening the closed core. Profiles are registry-published extension families
with schemas and evaluation-semantics documents. Neither an extension body nor
a successful extension verdict is authority.

## The envelope

Every artifact's extension envelope is exactly:

```json
{"critical": {"namespace": body}, "optional": {"namespace": body}}
```

- A namespace is at most 512 UTF-8 bytes, lowercase reverse-DNS-plus-path form
  with exactly one slash (for example `com.example/pricing-indexed`).
- An artifact carries at most 32 namespaces total.
- A namespace may not occur in both regions.

## The compiled registry

`CharterAgreementProtocol.ExtensionRegistry` is compiled production data —
registry changes are package code releases, not file reads. Each entry carries
exactly `namespace`, `owner`, `criticality`, `state`, `schema_digest`,
`a2a_uri`, and `promoted_at_revision`. Lifecycle states are closed to
`reserved`, `active`, `deprecated`, and `retired`. Retired names remain
occupied and can never be reused — a namespace is a permanent identity.

Behavior by region and registration:

| Body | Critical region | Optional region |
|---|---|---|
| Registered, matching schema | validated against the exact compiled schema digest | validated; must also match criticality and placement |
| Unknown namespace | rejected — fail closed | retained byte-exactly, digest-covered, **quarantined**; facts retain only the namespace |
| Reserved or retired | rejected | quarantined like unknown |

Registered critical bodies must occupy their declared artifact surface
(revision vs receipt) and the supplied schema's canonical document digest must
equal the registry pin before validation runs.

## What shipped today

All shipped identities are RFC 2606 `example.com` example-class — example
owners, `example.com` declaration URIs, `com.example` namespaces — because
example content is the only content a protocol package can ship without an
owning authority:

- the active **indexed-price** term profile (critical, revision surface) and
  its **observation** profile (optional, receipt surface);
- the active schema-free **core receipt** profile;
- two **reserved** attestation-family names — reserved so real attestation
  work cannot collide with squatters; they define no bytes and CAP does not
  interpret their bodies;
- one **retired** example namespace that mechanically keeps retired-name reuse
  closed.

## The indexed-price profile

The shipped example profile defines portable pricing-term data — currency,
base amount, index reference, `index_plus_spread` formula, spread, bounds,
tolerance — and separate receipt observations. Its full member tables and the
ISO 4217 currency-list pin are specified in
[Indexed-price profile](../profiles/indexed-price.md).

The criticality split is normative: registry criticality is a stable namespace
property, so revision terms and receipt observations use separate namespaces.
CAP validates and binds the data; `term_satisfaction` stays in every facts
record's `not_verified` floor, and each host independently obtains index
observations, computes amounts, and applies its own operational policy.

## What profiles can and cannot define

Profiles may define revision term schemas, receipt-extension members, and
evaluation-semantics documents. They **cannot** define signature, acceptance,
precedence, or authority semantics — those surfaces are closed core members
outside extension bodies, so no extension can weaken verification. Changing an
assented formula requires a new Charter Revision and the normal bilateral
acceptance process.

## Quarantine in practice

When a receipt arrives carrying an optional namespace your registry release
does not know, verification still succeeds: the body is retained exactly and
digest-covered inside the decoded artifact, and the facts record exposes only
the namespace string. Your host decides what to do with unknown optional
evidence; CAP neither drops the bytes silently nor gives them meaning. The
certified corpus's `receipt-indexed-price-observation-quarantine` case proves
both retention and namespace-only facts projection.
