# Security considerations

CAP verifies signed, byte-exact evidence and never authorizes anything.
This document is the normative threat model for the core specification
(`core.md`); the repository's implementation-facing security boundary is
documented in `../docs/guides/security-model.md`.

## Asset and adversary model

The assets are the signed artifacts themselves: party descriptor key
histories, charter revisions, acceptances, termination notices, and
receipts. The adversary is any party able to craft or replay artifact
bytes: a counterparty, a compromised intermediary store, or a malicious
host. The protocol assumes authenticated channels are NOT provided by CAP
itself — distribution is out of scope; what CAP provides is the ability
to verify, byte-exactly and offline, that the artifacts you hold are the
artifacts that were signed, and to see the structural facts (forks,
contested views, supersession) they encode.

## The non-authorizing floor

Verification proves key-possession and structural statements only. Every
facts record carries a closed `not_verified` floor — tenancy, live
policy, authority, effect ownership, execution, billing, evaluation
truth, legal validity, term satisfaction, view completeness,
counterparty view, and wall clock — and omissions only ever accumulate.
No CAP output may be treated as authorization, adjudication, or an
observed effect. This floor is the protocol's primary security property:
a host that acts on CAP evidence does so on its own authority, with the
evidence in hand.

## Signature and key threats

- **Forged signatures.** Every attached artifact is Ed25519 over the
  exact RFC 7515 signing-input bytes under a key resolved from the
  declared descriptor history. Verification paths never skip or
  short-circuit the cryptographic check, and digest comparison is
  constant-time.
- **Key-confusion and typ confusion.** The protected header is closed to
  `alg`, `kid`, and `typ`; the `typ` value must match the expected
  artifact type for the call, preventing one artifact type from being
  replayed as another. The `kid` is a lookup hint with no authority;
  resolution always passes through the declared key history.
- **Non-canonical encodings.** Ed25519 non-canonical point encodings and
  all eight low-order torsion encodings are rejected for both public
  keys and signature `R` values before verification, closing the
  malleability and identity-confusion classes those encodings enable.
- **Key compromise.** Compromise of an active key lets the adversary
  sign as that party from the compromise instant. The protocol's answer
  is evidence, not prevention: descriptor succession with re-verified
  predecessor binding makes history append-only-and-checkable; equivoked
  positions (two signatures by the same descriptor and role at one
  revision number over different digests) surface as equivocation
  evidence with no winner selected. Rotating to a successor descriptor
  and countersigning a supersession repair is the recovery path.

## Fork, equivocation, and suppression threats

A verifier must never silently collapse a fork. Forked chain topology,
contested governing views, receipt chain conflicts, and superseded
descriptor positions are all reported as first-class facts; the mutation
battery proves that suppressing any of them turns the corpus red. The
designed non-goal: CAP does not adjudicate which sibling is "real" —
reporting both, with `contested` governance, is the honest answer inside
an unresolved fork, and unilateral host action there is out of model.

## Canonicalization and substitution attacks

All signed bytes are canonical JSON under a fixed, codec-enforced
grammar; member-order tricks, number-representation tricks, duplicate
names, and non-character code points are rejected at decode. Digests are
domain-separated so content cannot be replayed across domains
(`legal_text` content cannot substitute for a descriptor digest, and so
on), and digest-bearing members are cross-checked against recomputed
values rather than trusted.

## Extension surface

Unknown critical extension namespaces fail closed. Unknown optional
namespaces are retained byte-exactly and quarantined — never interpreted,
never entering a facts record — so a malicious optional body cannot
affect verification outcomes. Registered critical bodies validate against
the exact schema digest compiled into the registry (see
`registry-policy.md`).

## Resource-exhaustion posture

Every decoder and verifier operates under caller-supplied ceilings
(bytes, nesting, item counts, string lengths); inputs above a ceiling
are rejected, not buffered. The schema validator is a closed 16-keyword
subset with metered complexity and no regular-expression or network
fetching surface, so a crafted schema cannot become a ReDoS or SSRF
vector. Verification reads no clock and performs no I/O.

## Operational notes for implementers

- Never log rejected input: error codes are closed and value-free by
  design; keep it that way in host logging.
- Hosts that assemble compacts from externally produced signatures must
  post-verify the assembled artifact through CAP before use.
- The demo fixtures and corpus vectors are never trust anchors.
