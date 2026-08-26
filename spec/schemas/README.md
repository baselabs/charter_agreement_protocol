# Wire grammar schemas

CAP never authorizes.

This directory is the single normative machine grammar for CAP's externally
consumed wire formats. Every schema is written in the JSON Schema 2020-12
dialect restricted to the closed 16-keyword subset validated by
`AgentBlueprintProtocol.Schema` (the pinned development/test dependency):
`type`, `properties`, `required`, `items`, `enum`, `const`, `minimum`,
`maximum`, `minLength`, `maxLength`, `minItems`, `maxItems`,
`additionalProperties`, `oneOf`, `$defs`, and document-local `$ref`. No other
dialect file exists; there is no CDDL companion.

The schemas cover the five artifact claim sets (party descriptor, charter
revision, acceptance, termination notice, receipt), the extension envelope,
the compact-JWS protected header, the tagged-digest and timestamp grammar,
and the two externally consumed conformance wire documents (the corpus index
and the canonical report).

## What the schema layer expresses — and what it deliberately does not

The bounded subset has no `pattern` keyword, and string lengths in the
dialect count Unicode codepoints, not bytes. The schemas therefore express
member closure, JSON types, closed enumerations, numeric ranges, and item
cardinalities. The following are enforced by the codec and the normative text
(`spec/core.md`), never by these files:

- Character-set shape: tagged digests (`sha-256:` plus 43 base64url
  characters), Ed25519 public keys, key identifiers, blueprint identifiers,
  receipt profiles, and namespace form are byte-exact constraints. A schema
  can bound their length; it cannot spell their alphabet.
- Byte-exact string bounds where bytes and codepoints diverge (namespace
  bodies, hint URIs).
- Cross-field rules: conditional member presence (successor-only members),
  timestamp ordering, decision/outcome pairing, and genesis shape.
- Extension namespace cardinality and the critical/optional exclusivity
  invariant (the dialect has no `maxProperties`).

A value that validates against these schemas is grammatically well-formed;
it is not thereby a semantically valid artifact. Verification semantics live
in the codec and `spec/core.md`.

## Enforcement

`mix conformance.verify` parses every schema in this directory exactly once
per run and proves two directions over each: a positive (a live corpus or
report instance validates) and one constructed single-defect negative per
shipped constraint (dropped required member, unknown member, wrong type,
wrong enumeration, violated bound), each observed to fail. The completed
seeds inject grammar-valid values for optional members so every constraint
carries both directions.
