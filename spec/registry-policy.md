# Registry policy

CAP's extension and profile surface is registry-mediated and fail-closed.
This document states who may register what, how registered content is
bound, and how the surface may grow. The machine-enforced counterpart
lives in the extension registry compiled into the implementation and in
the digest-pinned schema layer (`schemas/`).

## Extension namespaces

Three artifact surfaces — the party descriptor, the charter revision,
and the receipt — carry exactly one extension envelope each: an object
with a `critical` and an `optional` region, each mapping namespaces to
bodies. The acceptance and termination claim sets are closed without an
envelope member; extensions for those surfaces are out of model. A
namespace is lowercase reverse-DNS-plus-path form with exactly one
slash, at most 512 UTF-8 bytes, at most 32 namespaces per artifact, and
a namespace never appears in both regions.

- **Unknown critical namespaces fail closed.** An implementer receiving
  an artifact with a critical namespace absent from their compiled
  registry must reject the artifact. There is no override.
- **Unknown optional namespaces are retained and quarantined.** The body
  survives verification byte-exactly and is named as quarantined; it is
  never interpreted and never enters a facts record.
- **Registered critical bodies are digest-pinned.** A registered
  namespace binds the exact schema digest its bodies must satisfy. A
  body that validates against a different schema — even a semantically
  equivalent one — is not the registered body.

## Who registers

The protocol owner maintains the registry. Registration of a critical
namespace requires: the namespace, its schema in the 2020-12 bounded
subset, the artifact surfaces it may appear on, and a lifecycle state.
Registration is additive; a published critical namespace is never
silently redefined — semantic changes register a new namespace, and the
errata policy governs verdict-changing corrections. Optional namespaces
need no registration to flow through verification (that is the point of
quarantine), but profile documents may still name them normatively.

## Receipt profiles

`receipt_profile` names the extension profile namespace that governs a
charter's receipts (for example `com.example.charter/default`). A
profile namespace is registered like any other; its schema constrains
the optional bodies receipts in that charter may carry. Verification
does not require profile knowledge — it enforces the envelope rules and
retains bodies — so a host with a newer registry interops with an older
charter's profile by quarantine.

## Attestation-profile alignment (non-normative)

External attestation ecosystems are stable, published, and adoptable
through this registry without protocol change: W3C Verifiable
Credentials 2.0 (W3C Recommendation, May 2025) as the interchange
backbone, GLEIF vLEI credential types for organizational identity, and
eIDAS 2.0 electronic attestations of attributes under Regulation (EU)
2024/1183. A future attestation profile registers namespaces that map
to those credential types; the protocol's closed member sets and
fail-closed envelope mean no such mapping requires a wire change.
Adoption trajectories are monitored, not baked in — see
`evolution.md`'s forward-looking notes.
