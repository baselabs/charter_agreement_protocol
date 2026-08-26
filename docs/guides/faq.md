# FAQ

**Can CAP approve or trigger a payment?**
No — that boundary is the product. CAP verifies signed, byte-exact agreement
evidence and returns structural facts with a closed `not_verified` floor
(authority, execution, billing, term satisfaction, and eight more). Your host
reads the facts and makes every decision. See [Security model](security-model.md).

**Why did my JSON library's output fail canonicalization?**
CAP is byte-exact by design: RFC 8785 canonicalization, no inter-token
whitespace, ECMAScript number spelling, UTF-16 member ordering. Semantic JSON
equivalence is not canonical equivalence — `Canonicalization.verify/1` accepts
received bytes only when re-encoding reproduces them exactly. Produce CAP
artifact bytes with `Canonicalization.encode/1`, never a general-purpose
encoder.

**Why is everything pinned to exact identities?**
Protocol conformance here is identity-exact: the certified corpus freezes real
ABP deployment digests and BAP grant bytes, and the release gate pins the exact
index bytes. A loose pin would let verification silently cover different bytes
than the ones certified. The durable identity is the exact Hex requirement
plus its registry checksum — and the published 0.1.0 checksum equals the
release gate's archive SHA, so the registry serves exactly the reviewed
bytes. See [Getting started](getting-started.md).

**How do I iterate against sibling repositories during development?**
Temporarily point the dependency at a local path in your working tree. The
release-candidate gate rejects committed `path:`/`git:` dependencies in CAP
itself by design — the committed contract stays registry-served — but a
working-tree override is invisible to it. Revert before committing.

**What do I do when `governing_revision` returns `:contested`?**
Treat it as a stop signal: two accepted branches are eligible at that instant
and CAP never selects a winner. The only repair is a later revision,
countersigned by both parties, naming every contested sibling in `supersedes`.
The [fork-repair notebook](../notebooks/fork-repair.livemd) walks it end to
end.

**My counterparty sent an extension namespace CAP doesn't know. Now what?**
If it arrived in the `critical` region, verification fails closed — by design;
unknown critical semantics must not pass. In the `optional` region the body is
retained byte-exactly and digest-covered, and the facts record exposes only
the namespace: quarantined, not dropped and not interpreted. See
[Extensions](extensions.md).

**Does CAP check that keys are still trustworthy today?**
No. Descriptor verification proves signed key continuity; there is no live
revocation oracle, and CAP reads no clock. If your trust model needs freshness,
your host supplies the revocation policy around the verified facts.

**Is the TypeScript verifier shipped in the package?**
No. The verifier is repository-side and excluded from the archive by the
package-boundary gate; the certified corpus and the Elixir CLI do ship. The
Elixir/TypeScript byte-identity is proven in CI over both the repository and
the unpacked-package corpus on every run.

**What exactly does `outcome: "effect_committed"` prove?**
That the issuing party's active charter key signed a receipt claiming the
decision was `accepted` and the outcome was `effect_committed`, bound to exact
revision coordinates, deployment digest, and grant digest. Effect truth stays
in the `not_verified` floor — the receipt is evidence, not an observation.

**Can I use CAP without both parties running CAP?**
Yes. Artifacts are portable bytes; any implementation that reproduces the
canonical forms can produce and verify them. That is precisely what the
independent TypeScript verifier demonstrates — a second implementation with
zero shared code, byte-identical projected facts.

**How do I report a security issue?**
See [SECURITY.md](../../SECURITY.md).

**Where is the package published?**
On Hex: [hex.pm/packages/charter_agreement_protocol](https://hex.pm/packages/charter_agreement_protocol).
The published 0.1.0 inner checksum equals the release-candidate gate's
archive SHA — the reviewed bytes are the shipped bytes. Building an archive
remains verification evidence only, never publication authority: the
repository still exposes no publish alias, and future releases require
separate explicit authorization.
