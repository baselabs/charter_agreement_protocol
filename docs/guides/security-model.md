# Security model

The security model is one sentence with a large mechanical surface behind it:
**CAP verifies signed, byte-exact evidence and never authorizes anything.**
This page is the precise boundary — what every verification proves, what it
structurally cannot prove, and the gates that keep that boundary closed.

## The non-authorizing floor

Every facts record — descriptor, acceptance, termination, revision, chain, and
receipt facts — is constructed through a single shared constructor that forces
this closed twelve-item `not_verified` floor:

- tenancy
- live policy
- authority
- effect ownership
- execution
- billing
- evaluation truth
- legal validity
- term satisfaction
- view completeness
- counterparty view
- wall clock

Additional omissions union on top (the revision-only receipt form adds
`:signature`, for example); nothing can remove or shrink the floor. When you
read a CAP facts record, the `not_verified` list is part of the answer, not a
caveat attached to it.

## What each verification proves — and never proves

| Verification | Proves | Never proves |
|---|---|---|
| Descriptor / descriptor chain | Signed key continuity, predecessor-bound transitions, signed fork evidence | Organizational identity, legal validity, authorization, current revocation status, attestation-target ownership |
| Acceptance | Exact signed assent claims over one revision, signer key active in the pinned descriptor | Legal validity, view completeness, current key revocation, authorization, term satisfaction |
| Termination notice | A pinned party signed a listed reason and pure effective-time coordinate | Delivery, receipt, legal effect, current revocation, that the effective time has arrived |
| Chain / governing revision | Structural view-relative facts; the unique governing digest at one caller-supplied instant, or `:contested`/`:none` | Global completeness, counterparty's view, any policy verdict |
| Receipt | Signed issuing-party evidence bound to exact revision coordinates, deployment digest, grant digest, decision/outcome, recomputed governance | Live grant state, authorization, execution, effect truth, legal validity, term satisfaction, wall-clock truth |

CAP reads no clock anywhere. "Now" is always a caller-supplied UTC instant.

## Key custody

The production package has no signing call, private-key parameter, signer
callback, signer module, or custody handle. The seam is:

1. CAP builds a signing input — the exact RFC 7515 message bytes plus the
   closed protected header.
2. **You** sign those bytes with your Ed25519 key, outside CAP.
3. `assemble_compact/2` revalidates the kind/header/payload/message
   relationship, accepts exactly one raw 64-byte external signature, and
   returns the compact.
4. Hosts must post-verify the assembled compact through CAP before returning
   it to service.

The set-aware producers additionally cold-verify your artifact set and refuse
coordinates that would manufacture equivocation or stale ancestry. These
guards constrain honest use relative to the supplied set — they cannot
constrain a dishonest signer or prove any view complete. See
[Verification semantics](verification.md).

## Cryptographic primitives and hardening

- **Ed25519 only** (`EdDSA`). Before the runtime primitive is invoked, CAP
  rejects noncanonical point encodings and all eight low-order torsion
  encodings for both public keys and signature `R`, and rejects signature
  scalars outside the canonical subgroup-order range — so the runtime never
  sees degenerate inputs.
- **Domain-separated SHA-256** (`SHA-256(domain || 0x00 || content)` over a
  closed domain set). The same bytes hash differently per artifact surface, so
  cross-surface digest substitution fails.
- **Constant-time digest comparison** — equal algorithm and width, every byte
  pair consumed through one XOR/OR accumulator, tested only after the full
  input. No early-exit shape.
- **SHA-256 known-answer tests** against the current NIST CAVP
  byte-oriented vectors (empty input, `d3`, `b4190e`) under FIPS 180-4. These
  verify the runtime primitive against published answers; they do not claim
  CAP itself has undergone CAVP validation.
- **Source censuses** pin CAP's domain separators and protected `typ` values
  and prove they remain disjoint from the consumed ABP and BAP package
  identities.

## Value-free errors and redacted inspection

Failures return `%CharterAgreementProtocol.Error{code, subject, detail}` with
a closed code vocabulary. Subjects contain protocol-owned names and
non-negative indexes — **never rejected values** — and details are absent or
protocol-owned. Verification failures are safe to log by construction.
Facts records implement redacted inspection so logs never expose retained
signed artifacts.

## Resource bounds

Untrusted input is bounded before parsing: caller-supplied decode ceilings
(bytes, depth, members, items, string sizes, artifact-set size — see
[Getting started](getting-started.md) for defaults and greatest selectable
values; the exact bound is accepted and bound-plus-one fails closed with
`:limit_exceeded`). The conformance CLI additionally caps itself at 64 files
and 32 MiB per corpus directory.

## Architecture enforcement

The boundary is not prose — it is gates that run in CI:

- the production-runtime battery rejects filesystem, calendar, wall-clock,
  shell/OS-escape, and dynamic-dispatch calls;
- source gates reject authorization-decision and term-evaluation vocabulary
  and require every explicit module to state its non-authorizing boundary;
- every public function, macro, and delegate requires a specification;
- every facts struct is constructed through the single omission-floor
  constructor;
- all Mix dependencies must be development/test-only and `runtime: false` —
  production is OTP `:crypto` alone.

See [Conformance](conformance.md) for the full gate battery and
[Protocol foundation](../protocol.md) for the normative statements.
