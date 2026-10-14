# Receipts and sibling protocols

A receipt is a signed record of one action, tied to the exact charter revision it was
taken under. It answers the questions an auditor asks later: which revision, which
deployment and which `grant` reference covered this action, and what did the issuing
party say happened? Anyone holding the receipt and the charter's artifacts can check
the answer again.

A receipt is an attached compact JWS with protected type `cap+receipt`. The issuing
party signs it with an active key from its party descriptor.

## Claims

| Member | Contract |
|---|---|
| `protocol_revision` | `1` through `3` |
| `charter_id` | the charter id (the genesis revision's digest) |
| `revision_number`, `revision_digest` | the exact revision the action was taken under |
| `issuing_party_role`, `agent_party_role` | roles the revision lists; they may be the same role |
| `deployment_digest` | the exact ABP deployment digest of the agent's party |
| `grant` | a typed reference, described below |
| `invocation_id` | your identifier for the action, 1 to 512 bytes |
| `decision` | `accepted` or `rejected` |
| `outcome` | `effect_committed`, `no_effect` or `indeterminate` |
| `occurred_at`, `recorded_at` | UTC timestamps; `recorded_at` may equal `occurred_at` but never precede it |
| `extensions` | the extension envelope, for receipt profiles |

`decision` and `outcome` combine in four ways only. `accepted` allows any of the three
outcomes. `rejected` requires `no_effect`. Any other pair fails with
`:cross_field_invalid`.

## The `grant` reference and BAP

The `grant` member is `{scheme, id, grant_digest}`, where `scheme` is `bap` or `host`:

- a `bap` reference must carry `grant_digest`;
- a `host` reference may leave it out.

The Bounded Authority Protocol (BAP) computes `ath` as the unpadded base64url SHA-256
of the complete BAP compact it received. CAP writes the same hash in its tagged
form, so `grant_digest` is `"sha-256:"` followed by the `ath` value.

Both spellings decode to the same 32 bytes. CAP's test suite computes `ath` with the
published `bounded_authority_protocol` 0.8.0 package and checks it against the digest
the receipt fixtures carry. The composition is checked against BAP's own code.

CAP checks that `grant_digest` is well formed and covered by the receipt's signature.
It does not read or interpret the BAP compact the digest names.

## ABP deployment bindings

A charter revision's `abp_bindings` names, for each party role, the agent build and
deployment that party runs. A receipt's `deployment_digest` must equal the binding for
its `agent_party_role`. The test suite decodes the Agent Blueprint Protocol's
published golden deployment with `agent_blueprint_protocol` 0.1.1 and checks that the
digests in CAP's fixtures equal the ones ABP computes.

Neither sibling package is a runtime dependency. Both are pinned exactly, for
development and tests only.

## Verifying a receipt

`CharterAgreementProtocol.verify_receipt/3` takes the receipt compact, a context and
your limits. The context decides how much CAP can check.

**Full chain context** (`ChainFacts` from `verify_chain/5`). This is the form to use.
CAP verifies the chain again from the bytes the facts retain, then:

- resolves the issuing role to an active key in that party's descriptor and verifies
  the signature under the algorithm the key's registry row names;
- checks the charter id, revision number, both roles and the agent's deployment
  binding against the revision the receipt names;
- computes the governing revision at `occurred_at` and compares it.

**Revision-only context** (a decoded `CharterRevision`). Use this when you hold the
revision but not the chain, for example before you have the counterparty's
descriptors. CAP checks that the claims and deployment match the revision. It cannot
check the signature or governance, so the facts add `:signature` to `not_verified`,
set `signing_key_id` to `nil`, and report `governing_match: :undetermined`.

After you produce a receipt, verify it with full chain context before you store or
send it. The revision-only form does not check the signature, so it cannot catch a
signature made with the wrong key.

### What the result tells you

- `governing_match` is `:match` when the receipt's revision governed at
  `occurred_at`, `:mismatch` when another revision did (or none did, for example after
  a termination), and `:undetermined` when the view is contested at that instant.
- `chain_conflict` is `:fork_evidenced` when the receipt names a revision you do not
  hold as accepted, at or below the highest accepted number. That means a sibling you
  have not seen. CAP reports it and selects no branch. Otherwise it is `:none`.
- `deployment_digest_matched` is `false` whenever the receipt names a revision you do
  not hold as accepted, because there is no binding in your view to compare against.

Only accepted revisions count when CAP decides which roles exist and which key belongs
to which role. A proposed revision is unsigned data, so it cannot swap roles to make a
counterparty's key look like the issuer's.

## What a receipt never proves

A valid receipt is evidence from an interested party. It does not prove that the
`grant` reference was live, that the action was allowed, that it ran, that its effect happened,
that it was legal, that the terms were met, that you hold every artifact, or what time
it really was. `outcome: "effect_committed"` is the issuing party's signed claim, not
an observation. See the [security model](security-model.md).

## Try it

The [charter tour notebook](../notebooks/charter-tour.livemd) produces a receipt and
verifies it as the counterparty would. The
[fork-repair notebook](../notebooks/fork-repair.livemd) verifies receipts inside an
unresolved fork. A receipt that names a revision you hold reports
`governing_match: :undetermined` with `chain_conflict: :none`, because two branches
compete at that instant. A receipt that names a sibling you have never seen reports
`chain_conflict: :fork_evidenced`.
