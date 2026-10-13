# Glossary

**Acceptance.** One party's signature over the exact bytes of one charter revision
(`cap+acceptance`). A revision counts as accepted when every party it lists has an
acceptance.

**Artifact.** One of the five things CAP verifies: party descriptor, charter revision,
acceptance, termination notice, receipt. Four are signed compact JWS; the charter
revision is unsigned canonical JSON.

**Artifact set.** The lists of revisions, acceptances, descriptors and terminations you
pass to `verify_chain/5`, or to `build_set/4` before producing an acceptance or a
termination.

**Canonical JSON.** The one byte spelling CAP accepts for a JSON value: members sorted,
no whitespace, numbers in their shortest form. Two parties holding the same value hold
the same bytes, so they compute the same digest. See
[implementing CAP](implementing.md) for the exact rules.

**Charter.** The agreement as a whole: every revision that shares one `charter_id`,
plus their acceptances and terminations.

**Charter id.** The digest of a charter's first revision. Every later revision carries
it.

**Charter revision.** One version of the terms, as canonical JSON. A later revision
names the one before it (`prev_revision_digest`) and has a higher `revision_number`.

**Compact.** The compact serialization of a signed JWS:
`header.payload.signature`, each part base64url without padding.

**Contested.** The answer `governing_revision/2` gives when more than one valid,
accepted revision could be in force and nothing resolves between them. CAP never
breaks the tie.

**Descriptor history.** A party's descriptors in order. Each one after the first is
signed by an active key from the one before it.

**Digest.** A domain-separated SHA-256 hash, written `sha-256:` followed by base64url.
The domain is part of the hashed input, so a revision and an acceptance never hash the
same bytes, and by SHA-256's collision resistance their digests do not match.

**Equivocation.** One party signing two different revisions at the same revision
number. CAP keeps both signatures as evidence and names no winner.

**Facts.** What a successful verification returns: a structured record of what was
proven, plus `not_verified`, the list of what was not.

**Fork.** Two valid successors of the same descriptor or revision. Proposed
revisions never govern, so only a fork between accepted revisions matters to
`governing_revision/2`: it returns `:contested` at an instant where both branches are
in effect and nothing covers them. The fork stays in the facts after a repair.

**Genesis.** The first descriptor in a party's history, or the first revision of a
charter.

**Governing revision.** The revision in force at a given instant: accepted, not
superseded, effective at that instant, the highest numbered, with no competing
branch, and not ended by a verified termination.

**Kid.** The key identifier in a signed artifact's header. It names which key in the
signer's descriptor made the signature.

**Limits.** The size bounds on what CAP will read (bytes, nesting depth, members,
items, artifact counts). Defaults apply unless you pass your own. See
[limits and profiles](limits-and-profiles.md).

**`not_verified`.** The twelve things no CAP result proves, carried on every facts
record. No option shortens the list.

**Party.** A participant in a charter, named in a revision by its role and the digest
of its descriptor.

**Party id.** The digest of a party's genesis descriptor. It stays the same across
every rotation in that party's history.

**Precedence declaration.** A revision member saying whether the legal text or the
machine-readable terms govern if they disagree. CAP records it and does not act on it.

**Profile.** Two different things share the word:
- a *capability profile* (`Capability.Profile`) narrows which algorithms and protocol
  revisions you accept;
- an *extension profile* (such as indexed price) defines a typed body that can appear
  in an artifact's extensions.

**Protocol revision.** The wire version an artifact declares (`protocol_revision`).
Revisions 1, 2 and 3 verify today; 3 adds ML-DSA signatures.

**Receipt.** A signed record of an action (`cap+receipt`), tied to the exact revision
and deployment it was taken under.

**Role.** The name a revision gives a party, such as `issuer` or `acceptor`. Roles in
one revision are unique.

**Signing input.** The exact bytes CAP asks you to sign for an artifact, returned by
the `*_signing_input` functions. You sign them outside CAP and pass the signature to
`assemble_compact/2`.

**Supersession.** A later revision that lists earlier accepted revisions in
`supersedes`. Once it is accepted, the superseded revisions stay in the history but no
longer compete. It repairs a fork when every competing branch that remains is its
ancestor; superseding only an unrelated revision, or only some branches, does not.

**Termination notice.** One party's signed notice (`cap+termination`) that the charter
ends at an instant, for a reason the revision lists. It closes the charter when it
names the revision in force at that instant.

**Verification semantics.** A number that identifies how CAP decides verdicts. It
changes when some input would get a different verdict or error code, when a default
limit changes, or when an input that returned a result now raises. Compare it, not the
package version, when you check stored results after an upgrade. See
[upgrading](upgrading-verification-identity.md).
