# Verification semantics

This page explains how CAP turns raw artifact bytes into facts, and how it treats
forks, supersession, the governing revision and termination. One rule runs through
all of it: CAP reports what the evidence shows and never picks a winner for you.

The terms used here (descriptor history, governing revision, contested, supersession)
are defined in the [glossary](glossary.md). The [artifacts reference](artifacts.md)
lists every member of every artifact.

## Every call starts from bytes

`CharterAgreementProtocol.verify_chain/5` takes four lists of raw bytes, in this
order, and then your limits:

- `revisions`: canonical charter revision bytes;
- `acceptances`: acceptance compacts;
- `descriptors`: party descriptor compacts for the histories the view names;
- `terminations`: termination notice compacts, often `[]`.

`build_set/4`, which you use before producing an acceptance or a termination, takes the
same lists in a different order: revisions, acceptances, terminations, descriptors.

CAP decodes and verifies every artifact on every call; artifact verdicts are not
cached. Runtime capability probes and their known-answer results are cached per VM. A member that points from one artifact to another (a digest, a role, a key id)
only tells CAP where to look. CAP still verifies the artifact it points at.

## Artifact-set bounds

Before CAP decodes anything or checks a signature, it bounds the whole view with two
limits:

| Limit | What it bounds | Default | Greatest value |
|---|---|---:|---:|
| `max_artifact_set_items` | the number of items in each of the four lists | 1,024 | 4,096 |
| `max_artifact_set_bytes` | the byte lengths of every artifact in all four lists, added together | 67,108,864 (64 MiB) | 1,073,741,824 (1 GiB) |

A view exactly at either ceiling verifies. One item or one byte above it returns
`:limit_exceeded`, with subject `["chain", "artifacts"]` for the item count and
`["chain", "bytes"]` for the byte total. Each artifact is then decoded under the
per-artifact limits (`max_bytes`, `max_depth` and the rest). See
[limits and profiles](limits-and-profiles.md) for all of them.

The byte bound matters most for post-quantum keys. An ML-DSA descriptor is many times
larger than an Ed25519 one, so a view can stay well under the item count and still be
large.

## Descriptor histories

`verify_descriptor_chain/2` takes every descriptor you hold for one party, in any
order:

- One history with no branches returns topology `:linear`. The newest descriptor is
  `:head` and every older one is `:superseded`.
- Two or more valid descriptors that name the same predecessor return `:forked`.
  Every descriptor in the result is marked `:contested`, and the sibling digests are
  kept as fork evidence.

Either way, CAP does not choose a branch, and it does not claim you hold every
descriptor that exists.

A descriptor history proves signed key continuity: each descriptor after the first
was signed by a key that was active in the one before it. It does not prove who the
party is, whether the party may act, whether a key has been revoked since, or that the
party controls anything an attestation names.

## Acceptances and equivocation

An acceptance is checked against the exact revision and the signer's verified
descriptor history:

- its claims must equal the revision's coordinates exactly: charter id, revision
  number, revision digest and predecessor digest;
- the descriptor digest and role it claims must be a party the revision lists;
- the `kid` in its header must name a key that is active in that descriptor.

If the same party, under the same descriptor and role, signs acceptances of two
different revisions at the same revision number, that is equivocation. CAP returns
`AcceptanceEquivocation` evidence holding both signed content digests and both
revision digests, and `winner` is `nil`.

Acceptances by different parties on competing branches are not equivocation. Each
party signed one thing. That case shows up as a contested view at the chain level.

An acceptance retains the `scope_status` and `signer_thumbprint` from its
pinned descriptor. Chain verification keeps signatures and vote credit
separately. The first applicable uncredited reason is `:arbiter_not_counted`,
`:role_outside_quorum`, or `:signer_outside_scope`. An outside acceptance
cannot satisfy a quorum or an assignment. Its signature remains visible.
An ordinary assignment assent can count for its party when that party
lies outside the quorum and its signer scope permits the artifact.

## Chain rules

Over the complete view you supply, `verify_chain/5` requires:

- exactly two descriptor histories in a legacy-only view, with every history
  named by some revision;
- every revision-8 party binding resolving to a distinct supplied history.
  A revision that names the same descriptor twice fails with `:revision_invalid`;
- unique revision digests and one genesis revision, whose digest is the charter id;
- every later revision naming, as `prev_revision_digest`, a revision in the view with
  the number one lower;
- every `supersedes` target being a revision of the same charter with a lower number,
  and every target named by a signed revision having sufficient verified signatures.

A legacy revision requires one verified acceptance for each of its two parties.
A revision-8 charter uses its declared acceptance quorum and, for successors,
the inherited quorum. An assignment also requires assent from all candidate
parties and each assignor. A successor needs an accepted immediate predecessor.
Revisions that have yet to meet their requirements remain proposed.

Two accepted revisions at the same number are fork evidence and make the view
contested. An accepted later revision can list contested branches in `supersedes`.
The superseded revisions stay in the history, along with the fork and equivocation
evidence, but they no longer compete. Nothing in CAP orders digests to break a tie.

## The governing revision

`governing_revision/2` takes the verified `ChainFacts` and an instant, either a UTC
`DateTime` or a `CharterAgreementProtocol.Timestamp`. It returns `{:ok, digest}`,
`{:ok, :contested}` or `{:ok, :none}`.

It considers accepted, non-superseded revisions that are in effect at that instant.
A revision is in effect from `effective_from` (inclusive) to `effective_until`
(exclusive), or with no end when `effective_until` is absent. Then:

- if one revision has the highest number and every other candidate is its ancestor,
  it returns that revision's digest;
- if competing branches remain, it returns `:contested`;
- if nothing is in effect, or a termination has closed the charter, it returns
  `:none`.

A `DateTime` in any zone other than UTC returns `:governing_invalid`.

CAP reads no clock. Two hosts that ask about the same instant with the same artifacts
get the same answer. Which instant to ask about ("now", the time of an invoice, the
time an action happened) is up to you.

## Termination closes the charter

For a legacy revision, one verified termination notice closes the charter if
it names the revision governing at its `effective_at`. Revision 8 requires
a termination quorum of eligible roles with the same revision, reason, and
effective instant. From the closing instant:

- `governing_revision/2` returns `:none` at and after `effective_at`;
- a receipt for an action at or after `effective_at` reports
  `governing_match: :mismatch`.

Before `effective_at`, the notice has no effect: governance follows the revision
windows and ancestry as if it were absent, so, for example, nothing governs before the
revision's `effective_from`. Closure never brings an older revision back into force.

A notice that names a revision that does not govern at its `effective_at` is still
valid signed evidence, and it stays in `termination_facts`. It does not close the
charter.

A notice with `scope_status: :outside` stays in `termination_facts` and
contributes no termination vote. The notice's descriptor digest fixes
the scope used for the computation.

## Checks when you produce artifacts

The two producers that depend on other artifacts, `acceptance_signing_input/2` and
`termination_signing_input/2`, verify the `ArtifactSet` you give them before they
build anything to sign. They return `:signing_refused` when:

- an acceptance would land at a revision number where the set already holds an
  acceptance of a different revision;
- an acceptance names a revision that neither descends from nor supersedes every
  accepted revision at the highest number;
- a termination names a revision that does not govern at the notice's own
  `effective_at`.

These checks stop you from creating equivocation or stale evidence from the artifacts
you hold. They cannot stop a counterparty that signs without them, and they cannot
prove your view is complete. A verifier still checks everything it receives.

## Repairing a contested view

To repair a contested view, meet the acceptance rules of a later revision
that covers every competing branch: each competing revision is either an ancestor of the new one
through `prev_revision_digest` or listed in its `supersedes`. Descending from one
branch and superseding the other is enough; listing every sibling in `supersedes` also
works. The [fork-repair notebook](../notebooks/fork-repair.livemd) runs one repair
from start to finish: the equivocation evidence, the contested answer, the repair
revision and its two acceptances, and the single governing digest afterward.

The governing answer is also per instant. If a competing revision's
`effective_until` passes, later instants can have a single governing revision without
any repair, while the fork stays recorded in the chain facts.

## What the facts contain

`ChainFacts` describe the view you supplied: the revision, acceptance, descriptor and
termination facts, the superseded digests, the fork evidence, and the topology. They
carry no answer that depends on time. You get that from `governing_revision/2`.

Every facts record also carries `not_verified`, the twelve things the record does not
prove. No option shortens it. The [security model](security-model.md) explains what
each one leaves to your application.

`build_set/4` verifies nothing. It only checks that each list holds binaries and
returns a typed `ArtifactSet` for the producers.
