# Security model

CAP verifies signed, byte-exact evidence and never authorizes anything. A successful
verification tells you what the artifacts prove. Whether that is enough to act on is
up to your application, and this page sets out where that line falls.

For the normative threat model, see the specification's
[security considerations](../../spec/security-considerations.md) and
[privacy considerations](../../spec/privacy-considerations.md).

## What CAP trusts

CAP trusts three things:

- the OTP runtime's `:crypto` module, and the OpenSSL it links, to compute SHA-256 and
  verify Ed25519 and ML-DSA signatures correctly;
- the bytes, limits and instant you pass to each call, as the whole input for that
  call;
- its own compiled tables: the signature algorithm registry, the extension registry
  and the schemas.

Nothing inside an artifact is trusted until CAP has verified it. A `kid`, a digest, a
role or a URI only tells CAP where to look. CAP has no runtime dependencies besides
OTP, reads no files, clock, network or environment while verifying, and keeps no state
between calls.

CAP does not trust any party, and it cannot tell you who a party is. A descriptor
history starts from a genesis key. Which real counterparty that key belongs to is
something you establish outside CAP.

## The `not_verified` list

Every facts record (descriptor, acceptance, termination, revision, chain, receipt and
fork evidence) is built by one shared constructor that always adds these twelve
entries to `not_verified`:

| Entry | What stays with your application |
|---|---|
| `tenancy` | which account or tenant the evidence belongs to |
| `live_policy` | whether your current policy allows what you are about to do |
| `authority` | whether anyone was permitted to act |
| `effect_ownership` | who owns an effect |
| `execution` | whether an action ran |
| `billing` | charges and payment |
| `evaluation_truth` | whether a computation or evaluation is correct |
| `legal_validity` | whether the agreement is legally valid |
| `term_satisfaction` | whether the terms were met |
| `view_completeness` | whether you hold every artifact that exists |
| `counterparty_view` | what the other party holds |
| `wall_clock` | what time it really is |

Some results add entries. A receipt verified with only a revision for context adds
`signature`, for example. Nothing removes one. Read `not_verified` as part of the
answer.

## What each verification proves

| Verification | Proves | Does not prove |
|---|---|---|
| Descriptor history | signed key continuity, each step bound to its predecessor, forks as signed evidence | who the party is, legal validity, permission to act, current revocation status, ownership of an attestation target |
| Acceptance | one party's signed assent to one exact revision, with a key active in the descriptor it names | legal validity, that you hold every artifact, current revocation status, permission to act, that terms were met |
| Termination notice | a listed party signed a listed reason and an effective instant | delivery, legal effect, current revocation status, that the instant has arrived |
| Chain and governing revision | facts about the view you supplied; the one governing digest at an instant you choose, or `:contested`, or `:none` | that the view is complete, what the counterparty holds, any policy outcome |
| Receipt | the issuing party's signed record, bound to exact revision coordinates, a deployment digest, a `grant` reference, a `decision` and an `outcome`, with governance computed at `occurred_at` | that the `grant` reference was live, permission to act, that the action ran, that its effect happened, legal validity, that terms were met, the real time |

## Host checklist

These are the parts of security that CAP leaves to your application. The
[integration guide](integration.md) shows how to do each one.

- **Check the runtime at boot.** Call `CharterAgreementProtocol.capabilities/0` once at
  startup. If a row you rely on reports `verifiable: false` (ML-DSA needs OTP linked
  against OpenSSL 3.5 or later), refuse to start, or narrow what you accept with a
  `Capability.Profile`. On such a runtime, an ML-DSA artifact fails with
  `:algorithm_unsupported_on_substrate` when its signature is reached. That is
  neither `:signature_invalid` nor a pass: the checks before the signature passed,
  but whether the signature is valid is unknown.
- **Verify after you produce.** After `assemble_compact/2`, verify the compact through
  CAP before you store or send it. For a receipt, use full chain context, because the
  revision-only form does not check the signature. `charter_agreement_signer`
  verifies each artifact it signs before returning it, and checks the signature
  against the public key of the key it used.
- **Pin your trust anchors.** Decide outside CAP which genesis descriptor (its
  `party_id`) belongs to each counterparty, store it, and check that the facts you get
  name that `party_id`. The shipped corpus and demo keys are test data. Never treat
  them as trust anchors.
- **Own the time source.** CAP reads no clock. Pass an instant from a clock you trust,
  and store the instant you asked about next to the answer.
- **Handle revocation yourself.** CAP has no revocation service. An acceptance
  verifies against the descriptor it names, so it still verifies after the party
  retires that key in a later descriptor. Acceptance facts carry `descriptor_position`
  (`:head`, `:superseded` or `:contested`) so you can see where the named descriptor
  sits in the history you hold. If freshness matters, get the counterparty's latest
  descriptor history and apply your own policy.
- **Set limits for your traffic.** Start from `Limits.default/0` and narrow it to the
  sizes you expect. CAP bounds work on binaries you have already read; bounding the
  read itself (request size, stream length) is your side.
- **Keep every artifact you receive.** CAP sees only the view you pass in. Store
  conflicting artifacts too: they are the evidence. Treat `:contested` as a stop, not
  a choice to make.
- **Log codes, not artifacts.** CAP errors are safe to log as they are. Facts print as
  `#...<redacted>`, so log the fields you need on purpose, and keep raw artifacts out
  of general logs.

## Key custody

CAP never holds a private key. The production package has no signing call, no
private-key parameter, no signer callback and no custody handle. The flow is:

1. CAP builds a signing input: the exact RFC 7515 message bytes and the closed
   protected header.
2. You sign those bytes with your key, outside CAP: `Ed25519`, or `ML-DSA-65` when
   minting at `protocol_revision` 3.
3. `assemble_compact/2` checks the signing input again, accepts one raw signature of
   the exact length for its algorithm (64 bytes for `Ed25519`, 3,309 bytes for
   `ML-DSA-65`), and returns the compact.
4. You verify the compact through CAP before you use it.

The acceptance and termination producers also verify the artifact set you give them
and refuse to build a signing input that would create equivocation or stale evidence.
They protect you from mistakes with the artifacts you hold. They cannot constrain a
counterparty, and they cannot prove your view is complete. See
[verification semantics](verification.md).

## Cryptography

- **Ed25519** (`EdDSA` and `Ed25519` rows). Before the runtime primitive is invoked,
  CAP requires the exact key and signature lengths and applies the strict encoding
  checks that core specification section 4.2 sets for public keys and signatures.
- **Pure ML-DSA** (`ML-DSA-44`, `ML-DSA-65` and `ML-DSA-87` rows, from
  `protocol_revision` 3; FIPS 204, with the context set to the empty string per
  RFC 9964). The strictness rule is the registry row's exact public-key and signature
  byte lengths, checked before any cryptographic work. Verification needs OTP linked
  against OpenSSL 3.5 or later.
- **Domain-separated SHA-256.** Every artifact and content digest CAP computes is
  `SHA-256(domain || 0x00 || content)` over a closed set of domains. The same bytes
  form a different hash input for each artifact type, so, given SHA-256's collision
  resistance, a digest from one place cannot stand in for another. Two values are
  plain SHA-256 by design: the corpus index SHA-256, and a receipt's BAP
  `grant_digest`, which is BAP's `ath` in tagged form.
- **Constant-time digest comparison.** Both digests must have the same algorithm and
  width, and every byte pair goes through one XOR/OR accumulator that is tested only
  after the whole input. There is no early exit.
- **Checked against published vectors.** The test suite checks the runtime's SHA-256
  against the NIST CAVP byte-oriented vectors. That checks the primitive. It does not
  mean CAP has been through CAVP validation. The suite also checks that CAP's digest
  domains and protected `typ` values do not collide with those of the published ABP
  and BAP packages.

## Errors and logs

A failure is `%CharterAgreementProtocol.Error{code, subject, detail}`. The codes are a
closed set. A subject holds only protocol-owned names and non-negative indexes, never
a value from the rejected input, and a detail is absent or protocol-owned. You can log
a verification failure as it is. See [handle errors](error-codes.md) for every code.

Facts records and artifact sets implement redacted inspection, so printing one shows
`#CharterAgreementProtocol.ChainFacts<redacted>` instead of the signed artifacts it
holds.

## Resource bounds

CAP checks input bytes and artifact-set sizes before it parses anything, and nesting
depth, member and item counts and string sizes while it parses. You choose the ceilings (bytes,
nesting depth, members, items, string sizes, artifact-set items and bytes) within
compiled maximums. A value exactly at a ceiling is accepted, and one above fails with
`:limit_exceeded`. [Limits and profiles](limits-and-profiles.md) lists every default
and maximum.

The conformance CLI, the one part of the package that reads files, also caps itself
at 64 files and 32 MiB per corpus directory.
