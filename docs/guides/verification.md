# Verification semantics

How CAP computes structural facts from raw bytes, and the exact semantics of
forks, contested views, supersession, and governing revisions. The theme
throughout: CAP reports evidence and never selects a winner on your behalf.

## Everything is reverified from bytes

`CharterAgreementProtocol.verify_chain/5` accepts complete caller-supplied
lists of canonical revision bytes, attached acceptances, Party Descriptor
compacts, and termination compacts, plus explicit limits. It re-decodes and
re-verifies every artifact; raw routing claims inside artifacts never establish
trust. Set sizes are bounded by `max_artifact_set_items` — the exact ceiling is
accepted, ceiling plus one returns `:limit_exceeded`.

## Descriptor histories

`verify_descriptor_chain/2` accepts the complete in-view descriptor set in any
order:

- One reachable history returns topology `:linear`; every non-head descriptor
  is marked `:superseded`.
- Two or more individually valid descriptors naming the same predecessor
  return `:forked`; all returned descriptor facts are marked `:contested` and
  the sibling digests are retained as signed fork evidence.
- The verifier never selects a winner and never claims the caller's view is
  globally complete.

Descriptor verification proves signed key continuity only — not organizational
identity, legal validity, authorization, current revocation status, or
ownership of an attestation target.

## Acceptances and equivocation

A single acceptance is verified against the exact revision and the
reconstructed descriptor chain: chain coordinates must match exactly, the
signer's role must be one of the revision's two bound party roles, and the
protected `kid` resolves only against a key active in the pinned descriptor.

Two individually verified acceptances from the same Party Descriptor and role
at one charter/revision number over **different revision digests** produce
`AcceptanceEquivocation` evidence: both signed content digests and both
revision digests are retained, and `winner` is `nil`. Acceptances by *different
parties* on competing branches are set-level contested-view evidence, not
equivocation — only a party contradicting itself is equivocation.

## Chain-level rules

`verify_chain/5` enforces, over the complete supplied view:

- exactly two distinct descriptor histories matching the revision's two bound
  roles;
- unique revision digests, one genesis defining the charter identity, every
  successor binding the exact prior-numbered digest;
- supersession targets existing in the same charter at a lower number; and
- a revision is **accepted** only when both bound party-role pairs have one
  verified Acceptance.

Signed same-number siblings remain fork evidence and make the active view
contested. An accepted successor may explicitly supersede accepted
lower-numbered branches: historical fork and equivocation evidence is
retained, while the named branches lose current precedence. Digest ordering
never selects a winner.

## Governing computation

`governing_revision/2` takes the verified `ChainFacts` and a caller-supplied
UTC `DateTime`:

- returns the highest effective **accepted** revision on one ancestry;
- returns `:contested` when multiple branches are eligible at that instant;
- returns `:none` when nothing is eligible;
- effective intervals are start-inclusive and end-exclusive.

CAP reads no clock. Two hosts asking about the same instant with the same view
get the same answer; hosts asking about different instants get
instant-correct answers — "now" is a caller decision.

## Termination closure

A verified Termination Notice closes the charter at and after its
`effective_at` **only when the notice names the unique governing revision at
that instant**. Closure never reactivates an older revision. A notice that
names a non-governing revision is still valid signed evidence — it just does
not close the chain in the verifier's view.

## The honest-signer seam

Signing-input producers (`acceptance_signing_input/2`,
`termination_signing_input/2`) cold-verify the caller's `ArtifactSet` first and
refuse coordinates that would manufacture equivocation or stale ancestry: the
Acceptance producer refuses a charter number already occupied by an acceptance
for another digest and refuses candidates whose ancestry excludes any maximum
dual-accepted head; the Termination producer requires its named revision to be
the unique governing revision at the notice's own `effective_at`. These guards
constrain honest signers relative to the supplied set — they cannot constrain
a dishonest signer or prove the view complete.

## The only no-tie-break repair

A contested view is resolved exactly one way: both parties countersign a later
revision that names each contested sibling in `supersedes`. The
[fork-repair notebook](../notebooks/fork-repair.livemd) walks the full
sequence — equivocation evidence, contested governing view, countersigned
repair, unique governing digest.

## What the returned facts contain

`ChainFacts` are structural and view-relative: reverified revision,
acceptance, descriptor-chain, termination, supersession, and fork facts — and
no time-dependent verdict. Every facts record carries the closed
twelve-item `not_verified` floor (see [Security model](security-model.md)),
and `build_set/4` — which only constructs a typed raw set without verifying —
reports all twelve as not verified.
