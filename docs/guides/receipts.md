# Receipts

A Receipt binds one signed action to the exact agreement state that governed
it. It is the artifact an auditor recomputes years later to answer "which
charter revision, which deployment, and which grant governed this action, and
what did the acting party claim happened?"

A Receipt is an attached compact JWS with protected type `cap+receipt`, signed
by the issuing party's charter key.

## Claims

| Member | Contract |
|---|---|
| `protocol_revision` | protocol data value `1` |
| `charter_id` | the charter identity (genesis revision digest) |
| `revision_number`, `revision_digest` | exact revision coordinates |
| `issuing_party_role`, `agent_party_role` | the two bound roles |
| `deployment_digest` | one exact ABP deployment digest |
| `grant` | typed grant reference, below |
| `invocation_id` | caller-owned invocation identifier |
| `decision` | `accepted` or `rejected` |
| `outcome` | `effect_committed`, `no_effect`, or `indeterminate` |
| `occurred_at`, `recorded_at` | pure UTC; `recorded_at` may equal but never precede `occurred_at` |
| `extensions` | the receipt-profile extension envelope |

Decision/outcome pairs are closed: **accepted** may report `effect_committed`,
`no_effect`, or `indeterminate`; **rejected** requires `no_effect`.

## Grant references and BAP `ath` composition

The grant reference is `{scheme, id, grant_digest?}`:

- A `bap`-scheme reference **requires** the digest.
- A host-scheme reference may omit it.

BAP computes `ath` as the unpadded base64url SHA-256 of the complete received
grant compact; CAP uses the tagged form. The exact composition is:

```elixir
grant_digest = "sha-256:" <> ath
```

Decoding both spellings yields the identical 32 digest bytes. The frozen
conformance vector recomputes this against the exact published
`bounded_authority_protocol` 0.1.2 package — a self-round-trip is never called
conformance. Both sibling pins are development/test-only and runtime-disabled;
production CAP remains OTP-crypto-only.

## Verification

`CharterAgreementProtocol.verify_receipt/3` takes the receipt compact, a
context, and limits:

- **Full `ChainFacts` context** — the chain is reverified from retained bytes
  before use. The issuing role must resolve to one active descriptor key and
  the Ed25519 signature must verify. Charter identity, revision number, both
  party roles, and the agent role's deployment binding must match the
  recognized revision exactly. Governance is recomputed at `occurred_at`.
- **Revision-only context** — proves structural revision/deployment equality
  without descriptor keys or a chain view. Its facts add `:signature` to
  `not_verified`, set `signing_key_id` to `nil`, and report governance as
  `:undetermined`. Hosts use this form for post-sign verification, then
  re-verify with full chain context.

### Governance and fork results

- `governing_match` is `:match`, `:mismatch`, or `:undetermined` when the view
  is contested.
- An unrecognized revision digest at or below the accepted head returns
  `chain_conflict: :fork_evidenced`; no branch is selected.
- Only bilaterally accepted revisions contribute recognized revision status,
  role membership, or role-to-descriptor key resolution — a proposed (unsigned)
  revision is data and cannot swap roles to promote a counterparty key.

## ABP deployment bindings

The receipt's `deployment_digest` must equal the revision's `abp_bindings`
entry for the agent party role. The frozen vector decodes ABP's published
golden deployment with exact package `agent_blueprint_protocol` 0.1.1 and
requires CAP's frozen content and deployment digests to match the package's
recomputed output — binding CAP to the real ABP identity, not a lookalike.

## What a receipt never proves

A valid receipt is interested-party evidence. It never proves live grant state,
authorization, execution, effect truth, legal validity, term satisfaction, view
completeness, or wall-clock truth — `outcome: "effect_committed"` is the
issuer's signed claim, not an observed effect. See
[Security model](security-model.md).

## Try it

The [charter-tour notebook](../notebooks/charter-tour.livemd) ends with receipt
verification; the repository demo (`mix run examples/supplier_fork_demo.exs`)
cross-checks an action receipt against a contested chain and reports
`governing_match: :undetermined` with `chain_conflict: :none` — the exact
signature of action evidence inside an unresolved fork.
