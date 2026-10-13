# FAQ

**Can CAP approve or trigger a payment?**
No. CAP verifies signed agreement evidence and returns facts. Every facts record lists
what it does not prove under `not_verified`, including `authority`, `execution`,
`billing` and `term_satisfaction`. Your application reads the facts and decides what
to do. See the [security model](security-model.md).

**Why did my JSON library's output fail canonicalization?**
CAP accepts one byte spelling for each JSON value: members ordered by UTF-16 code
unit, no whitespace between tokens, and numbers written the way ECMAScript writes
them. A general-purpose encoder usually differs in at least one of these, and JSON
that means the same thing is not the same bytes. `Canonicalization.verify/1` accepts
received bytes only if encoding them again gives the same bytes. To produce bytes, use
`Canonicalization.encode_plain/1` for plain maps and lists, or
`CharterAgreementProtocol.encode_charter_revision/1` for a revision.
[Implement CAP in another language](implementing.md) lists the exact rules.

**Why does a `*_signing_input` call return `:signing_input_invalid`?**
The most common cause is `protocol_revision` in your claims. Each signing algorithm
mints at one revision: `Ed25519`, the default, at 2, and `ML-DSA-65` at 3. Claims that
carry any other value are refused. The same error covers claims that fail the
artifact's own rules, such as a missing member. The [error guide](error-codes.md) lists
the causes.

**Do I need `charter_agreement_signer`?**
No, but it saves work. CAP builds the bytes to sign and checks the result, and you
can sign them with `:crypto` yourself. The signer takes your key handle, signs, and
verifies its own output before returning it. See
[produce and verify with the signer](produce-and-verify.md).

**Why do facts print as `<redacted>`?**
Facts records hold the signed artifacts they were built from, and redacted inspection
keeps those out of logs. Read the fields you need directly, for example
`facts.chain_topology` or `facts.not_verified`.

**What do I do when `governing_revision` returns `:contested`?**
Stop and treat it as unresolved. Two accepted branches compete at that instant, and
CAP does not pick one. To repair it, both parties accept a later revision that covers
every competing branch: each one is either an ancestor of the new revision through
`prev_revision_digest` or listed in its `supersedes`. The
[fork-repair notebook](../notebooks/fork-repair.livemd) walks through one repair. The
answer is per instant: when a competing revision's `effective_until` passes, a later
instant may have a single governing revision again, while the fork stays recorded in
the chain facts.

**What does `:none` mean?**
No revision is in force at that instant. Either nothing accepted has taken effect yet,
the in-force revision has ended, or a verified termination notice closed the charter.
See [verification semantics](verification.md).

**My counterparty sent an extension namespace CAP doesn't know. Now what?**
In the `critical` region, verification fails, because a critical namespace must be
understood. In the `optional` region, the body is kept byte for byte, still covered by
the signature, and the facts name only the namespace. CAP neither drops it nor
interprets it. See [extensions and profiles](extensions.md).

**Does CAP check that keys are still trustworthy today?**
No. A descriptor history proves signed key continuity. CAP has no revocation service
and reads no clock. If you need freshness, get the counterparty's latest descriptor
history and apply your own policy around the facts.

**What does `outcome: "effect_committed"` prove?**
That the issuing party signed a receipt saying the `decision` was `accepted` and the
effect was committed, bound to exact revision coordinates, a deployment digest and a
`grant` reference. Whether the effect happened stays in `not_verified`. The receipt is
the issuer's claim, not an observation.

**Why does verification fail with `:algorithm_unsupported_on_substrate`?**
Your runtime cannot check the signature's algorithm. The checks that ran before the
signature check passed, but whether the signature is valid is unknown: a forged
signature of the right length gets the same error, so never treat the artifact as
verified. ML-DSA needs OTP linked against OpenSSL 3.5 or later. Call
`CharterAgreementProtocol.capabilities/0` at boot to see what your runtime can verify,
and verify the artifact again on a runtime that can.

**After I upgrade CAP, are my stored results still valid?**
Compare the verification semantics number, not the package version. It changes when
some input would get a different verdict or a different error code, when a default
limit changes, or when an input that returned a result now raises. Store it, with the
limits and profile you used, beside each result. [Upgrade and persist verification identity](upgrading-verification-identity.md)
explains what to store.

**Do both parties have to run this package?**
No. Artifacts are bytes, and any implementation that follows the specification can
produce and verify them. `@charter-agreement-protocol/verifier` on npm is a separate
TypeScript verifier that shares no code with this package. To write your own, start
with [implement CAP in another language](implementing.md) and
[the conformance corpus](conformance.md).

**How do I report a security issue?**
Follow [SECURITY.md](../../SECURITY.md).
