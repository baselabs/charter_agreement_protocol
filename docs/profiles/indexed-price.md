# Indexed-price profile

This page specifies the indexed-price profile that ships with CAP as an example. It
defines portable data shapes only. It does not authorize a price, decide whether an
observation meets a term, carry out any effect, or claim legal validity.

## Namespaces and placement

| Namespace | State | Region | Artifact |
|---|---|---|---|
| `com.example/pricing-indexed` | active | `critical` | charter revision |
| `com.example/pricing-indexed-observation` | active | `optional` | receipt |

The terms and the observations use two namespaces because criticality belongs to a
namespace. One name cannot be critical in a revision and optional in a receipt. Both
names reverse `example.com`, which RFC 2606 reserves for documentation and examples.
Their declaration URIs are identifiers only, and CAP never fetches them.

## Revision terms

The critical body is a closed object with these members:

| Member | Required | Contract |
|---|---:|---|
| `currency` | yes | one alphabetic code from the pinned ISO 4217 list below |
| `base_amount_minor` | yes | integer, 0 through 9,007,199,254,740,991 |
| `index` | yes | closed object, described below |
| `formula` | yes | exactly `index_plus_spread` |
| `spread_bps` | yes | integer, -10,000 through 10,000 |
| `floor_amount_minor` | no | integer, 0 through 9,007,199,254,740,991 |
| `cap_amount_minor` | no | same range; when both bounds are present, cap is at least floor |
| `tolerance_bps` | yes | integer, 0 through 10,000 |

`index` is a closed object with exactly these three members, all required:

| Member | Contract |
|---|---|
| `series_document_digest` | tagged SHA-256 digest (`sha-256:` and 43 base64url characters) |
| `series_id` | UTF-8 string, 1 to 128 bytes |
| `observation_lag_days` | integer, 0 through 90 |

A member out of range, or a `currency` or `formula` not in its list, fails with
`:constraint_violation`. A missing required member fails with `:missing_required`, and
an extra member with `:unknown_member`. Any problem inside `index` fails with
`:nested_invalid` on the `index` member. A cap below the floor fails with
`:cross_field_invalid`.

### The currency list

The `currency` list is a copy of the official ISO 4217 List One, published by SIX as
the ISO 4217 Maintenance Agency, taken on August 25, 2026, when the profile was added.
It holds 178 codes, including fund codes such as `BOV` and the `X` codes such as `XAU`
and `XTS`. The list is compiled into the package. A change to it is a new CAP release,
and it moves the schema and registry digests. Verification reads no network or file to
check a code.

Sources:

- [RFC 2606, Reserved Top Level DNS Names](https://www.rfc-editor.org/rfc/rfc2606)
- [ISO 4217 currency codes](https://www.iso.org/iso-4217-currency-codes.html)
- [SIX data standards and official ISO 4217 lists](https://www.six-group.com/en/products-services/financial-information/market-reference-data/data-standards.html)

## Receipt observations

The optional body is a closed object with these members, all required:

| Member | Contract |
|---|---|
| `observed_index_digest` | tagged SHA-256 digest |
| `observation_instant` | UTC RFC 3339 timestamp ending in uppercase `Z` |
| `computed_amount_minor` | integer, 0 through 9,007,199,254,740,991 |

Receipt facts name the namespace only. The amounts stay inside the signed receipt and
do not enter receipt facts or redacted inspection.

## How hosts evaluate it

The accepted charter revision fixes the formula and the tolerance. When an order or
invoice comes due, each host gets the named index observation itself, computes the
amount, and applies its own policy. CAP checks the syntax, the schema digest, the
signatures, the digests and the revision coordinates, and nothing else.

So:

- `term_satisfaction` stays in every CAP facts record's `not_verified` list;
- a valid receipt is evidence from an interested party, not proof that the amount was
  computed correctly or that the other party agrees with it;
- an observation body cannot change the revision's formula, precedence, acceptance or
  signature rules;
- changing an agreed formula takes a new charter revision that both parties accept.

If you use this profile for real money, your application evaluates the terms itself.
CAP's format checks do not do that for you.

See [extensions and profiles](../guides/extensions.md) for how the registry handles
these namespaces.
