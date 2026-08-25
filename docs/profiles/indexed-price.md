# Indexed-price profile

This document specifies the shipped RFC 2606 example-class indexed-price
profile. It defines portable data shapes only. It does not authorize a price,
decide whether an observation meets a term, execute an effect, or claim legal
validity.

## Namespaces and placement

- `com.example/pricing-indexed` is an active **critical** Charter Revision
  extension.
- `com.example/pricing-indexed-observation` is an active **optional** Receipt
  extension.

The split is normative. Registry criticality is a stable namespace property;
one name cannot be critical in a revision and optional in a receipt. Both names
reverse `example.com`, which RFC 2606 reserves for documentation and examples.
Their declaration URIs are identifiers only and CAP never dereferences them.

## Revision terms

The critical body is a closed object with these members:

| Member | Required | Contract |
|---|---:|---|
| `currency` | yes | one current ISO 4217 alphabetic code compiled from SIX List One |
| `base_amount_minor` | yes | integer, 0 through 9,007,199,254,740,991 |
| `index` | yes | closed object described below |
| `formula` | yes | exactly `index_plus_spread` |
| `spread_bps` | yes | integer, -10,000 through 10,000 |
| `floor_amount_minor` | no | integer, 0 through 9,007,199,254,740,991 |
| `cap_amount_minor` | no | same range; when both bounds exist, cap is at least floor |
| `tolerance_bps` | yes | integer, 0 through 10,000 |

`index` contains exactly:

| Member | Contract |
|---|---|
| `series_document_digest` | tagged SHA-256 digest |
| `series_id` | UTF-8 string, 1–128 bytes |
| `observation_lag_days` | integer, 0–90 |

The alphabetic currency list is a release-pinned copy of the official ISO 4217
Maintenance Agency List One fetched on 2026-08-25. SIX states that it is the
official Maintenance Agency and recognized authoritative source for ISO 4217
currency-code designations. A list change therefore requires a reviewed CAP
registry/schema code release and moves the schema and registry digests; no
runtime network or file read participates.

Primary sources:

- [RFC 2606, Reserved Top Level DNS Names](https://www.rfc-editor.org/rfc/rfc2606)
- [ISO 4217 currency codes](https://www.iso.org/iso-4217-currency-codes.html)
- [SIX data standards and official ISO 4217 lists](https://www.six-group.com/en/products-services/financial-information/market-reference-data/data-standards.html)

## Receipt observation evidence

The optional body is a closed object containing:

| Member | Contract |
|---|---|
| `observed_index_digest` | required tagged SHA-256 digest |
| `observation_instant` | required uppercase UTC RFC 3339 timestamp ending in `Z` |
| `computed_amount_minor` | required integer, 0 through 9,007,199,254,740,991 |

Receipt facts retain the namespace only. Commercial values remain inside the
signed Receipt artifact and do not enter facts records or redacted inspection.

## Evaluation semantics

The accepted Charter Revision binds the formula and tolerance. At an order or
invoice boundary, each host independently obtains the named index observation,
computes the amount, and applies its own operational policy. CAP verifies only
the syntax, schema pin, artifact signatures, digests, and revision coordinates.

Consequently:

- `term_satisfaction` remains in every CAP facts record's `not_verified` floor;
- a valid Receipt is interested-party evidence, not proof the computation was
  correct or mutually accepted;
- an observation body cannot change the revision formula, precedence,
  acceptance, or signature rules; and
- changing an assented formula requires a new Charter Revision and the normal
  bilateral acceptance process.

Production use for money requires host-side independent evaluation and the
applicable legal/commercial review; CAP's format checks do not substitute for
either.
