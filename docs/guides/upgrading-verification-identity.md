# Upgrade and persist verification identity

If you store charter artifacts and verify them again later, you need to know
whether a newer CAP release would reach the same results. CAP publishes that
as data. This page says what to store, what to compare when you verify again,
how releases map to verification semantics, and what to change for each
upgrade from 0.3.x to 0.5.0.

## What to store next to the artifacts

Store the artifact bytes exactly as received, and with them the identity of
the verification that accepted them.

| Value | Where to read it | On replay |
|---|---|---|
| `verification_semantics_version` | `ReleaseIdentity.verification_semantics/0`, or the release manifest | compare |
| the limits you used | your own `Limits` value; the manifest lists the defaults and maximums | compare |
| the profile you used, if any | your own `Capability.Profile` value | compare |
| `signature_registry_digest` | `Digest.to_tagged(Algorithm.registry_digest())`, or the manifest | compare |
| each artifact's `protocol_revision` and `alg` | the `protocol_revision` and `alg` fields of its facts record | compare |
| `spec_digest` | the manifest | record only |
| `corpus_digest` | the manifest | record only |
| `package_version` | the manifest | record only |
| the package checksum | your `mix.lock` | record only |

The release manifest ships in the package at `priv/release-metadata.json`.
Read it with
`Application.app_dir(:charter_agreement_protocol, "priv/release-metadata.json")`.
Unknown members may appear in later releases; ignore them.

Revision facts have no `alg`: a Charter Revision is unsigned. The signed
artifacts (descriptors, acceptances, termination notices and receipts) carry
both values. [Recipes](recipes.md) builds this record in code.

## Why compare some values and only record others

The verification semantics version names the verdict function: which inputs
pass, which fail, and with which error code. It moves to a new value whenever
any of these change against the previous release:

- an input that passed now fails, or one that failed now passes;
- the error code for an input changes;
- a `Limits.default/0` value changes;
- an input that returned a result now raises.

So if the semantics version, your limits, your profile, the signature
registry digest and each artifact's `protocol_revision` and `alg` are all
unchanged, the same bytes give the same result. Error subjects, the
`:algorithm_unsupported_on_substrate` diagnostic and the fields of facts
records are outside this identity: compare error codes, not subjects, and
expect facts records to gain fields.

The other values move without any change in results:

- `spec_digest` identifies the specification text. An editorial correction
  moves it, and `spec/changelog.md` lists each one. Any change in results
  also moves the semantics version, so comparing `spec_digest` adds nothing.
- `corpus_digest` identifies the conformance corpus, which grows when new
  cases are added.
- `package_version` and the checksum change with every release.

Keep these for supply-chain records. If you compare them on replay, every
upgrade looks like a conflict, including releases that change nothing you
depend on.

## Verify again after an upgrade

1. Read the stored bytes and the stored identity.
2. Verify the bytes with the current release, using the stored limits and
   profile.
3. If the semantics version and the other compared values match, expect the
   same result as before. A different result is a defect; report it.
4. If the semantics version differs, read the transitions between the two
   versions (next section). Each one names the class of inputs whose result
   changed. Treat the new result as a new verification and store it with the
   new identity.

## Semantics by release

```elixir
alias CharterAgreementProtocol.ReleaseIdentity

current = ReleaseIdentity.verification_semantics()

releases =
  for row <- ReleaseIdentity.compatibility() do
    {row.verification_semantics, row.package_versions, length(row.transitions)}
  end
```

`compatibility/0` returns one row per conformance corpus. Each row lists the
package versions, their semantics version, the corpus digest, the protocol
revisions they verify, and the transitions since the previous row. One
semantics version can span several rows: a release that adds corpus cases
without changing any result opens a new row with no transitions. The manifest
carries the same rows in its `compatibility` member.

| Semantics | Releases | What changed |
|---|---|---|
| 1 | 0.1.0 | first release |
| 2 | 0.2.0, 0.2.1 | revision-2 artifacts and the `Ed25519` name are accepted |
| 3 | 0.3.0, 0.3.1, 0.3.2 | ML-DSA-44, ML-DSA-65 and ML-DSA-87 are accepted at revision 3; seven timestamp members must be 1 to 64 bytes, so longer spellings fail; `max_artifact_set_bytes` (64 MiB by default) bounds a chain view, so larger views fail with `:limit_exceeded`; improper lists return a typed error instead of raising |
| 4 | 0.4.0, 0.4.1 | a Party Descriptor's `effective_from` must be 1 to 64 bytes, like the other timestamps |
| 5 | 0.5.0 | a charter's parties must be distinct: a revision that names one descriptor for two roles fails with `:revision_invalid`, and a chain view whose revision parties resolve to one party's descriptor history, or that holds a history no revision names, fails with `:chain_invalid` |

Releases before 0.4.0 shipped no manifest. Their rows are CAP's
classification of those releases, published afterward; their packages are
unchanged. Each mapping is checked on every release: every case in every
earlier corpus must give its recorded result under the current release,
except the listed transitions.

## Upgrade notes

### From 0.3.x to 0.4.0

- **Change the requirement.** `~> 0.3.0` does not accept 0.4.0. Use
  `~> 0.5.0` (see below), and apply the 0.5.0 notes as well.
- **Start storing the identity.** 0.4.0 adds the release manifest members
  `manifest_version`, `verification_semantics_version`, `limits`,
  `signature_algorithms`, `signature_registry_digest` and `compatibility`,
  and the `ReleaseIdentity` functions that return them.
- **Handle `:algorithm_unsupported_on_substrate`.** On a runtime that cannot
  verify ML-DSA, ML-DSA artifacts used to fail with `:signature_invalid`. They
  now fail with this code when the signature check is reached. It means the
  signature could not be checked: the checks before it passed, and whether
  the signature is valid is unknown. Call
  `capabilities/0` at boot to see which algorithms the runtime can verify.
- **Profiles are available.** `Capability.Profile` and a profile argument on
  every verify function narrow the algorithms and revisions you accept. They
  add three codes: `:invalid_profile`, `:algorithm_outside_profile` and
  `:revision_outside_profile`.
- **Facts carry revision and algorithm.** Each artifact's facts record has
  `protocol_revision`, and the records of signed artifacts have `alg`.
- **One result changed.** A Party Descriptor whose `effective_from` is longer
  than 64 bytes now fails. Check stored descriptors written by your own
  producer if it emits long fractional seconds.

### From 0.4.0 to 0.4.1

A packaging fix. The library code, the corpus and the semantics version are
unchanged. `docs/adr/release-identity.md` now ships in the package. Nothing to
change in your application.

### From 0.4.1 to 0.5.0

- **Change the requirement.** `~> 0.4.0` does not accept 0.5.0. Use
  `~> 0.5.0` (see below).
- **One result changed, so the semantics version moves to 5.** Both parties
  of a charter must be different parties. A revision that names the same
  descriptor for both roles now fails with `:revision_invalid`. A chain view
  fails with `:chain_invalid` when the revision's two parties resolve to one
  party's descriptor history (for example, a genesis descriptor and its own
  successor), or when it holds a descriptor history that no revision names.
  Verify stored charters again with 0.5.0 and store the new identity.
- **A narrowed profile reaches the context.** If you pass a profile to
  `verify_acceptance/5`, `verify_termination/5` or `verify_receipt/4`, it now
  applies to the supplied revision and the descriptor history or chain view,
  not only to the artifact itself, and a receipt checked against a bare
  revision is now checked against the profile as well. A context outside the profile fails with
  `:algorithm_outside_profile` or `:revision_outside_profile`. An artifact
  outside the profile whose `kid` names no key now fails with the profile
  code instead of the key lookup code, and `verify_descriptor/4` reports a
  predecessor outside the profile under the profile code instead of
  `:descriptor_chain_invalid`. On a runtime that verifies every algorithm,
  calls under the full profile, or with no profile, give the same results as
  before. On a runtime that cannot verify ML-DSA, `verify_descriptor/3` with
  an ML-DSA predecessor now returns `:algorithm_unsupported_on_substrate`
  instead of `:descriptor_chain_invalid`.
- **The corpus grows.** `corpus_digest` changes, and `compatibility/0` has a
  new 0.5.0 row. One semantics version can span several rows, so group rows by
  `verification_semantics` rather than assuming one row per version.
- **The specification text changed.** Among other edits, the security and
  privacy considerations now name every registered signature algorithm, so
  `spec_digest` changes. If you compared `spec_digest` on replay, stop: record
  it instead.
- **New helpers for producers.** `encode_charter_revision/1` builds a Charter
  Revision's canonical bytes from a plain claims map and checks them with the
  decoder. `Canonicalization.encode_plain/1` and
  `Canonicalization.from_plain/1` convert plain Elixir terms.
- **`priv/verifier-source.json` ships.** It names the TypeScript verifier
  repository and commit this release was checked against.

## Choose the dependency requirement

```elixir
{:charter_agreement_protocol, "~> 0.5.0"}
```

Before 1.0, `~> 0.5.0` accepts 0.5.0 and any later 0.5.x, and refuses 0.6.0.
A requirement for an older minor line does not move by itself: `~> 0.4.0`
never resolves to 0.5.0.

Your `mix.lock` fixes the exact version until you run `mix deps.update`. If
your application checks the package version at run time and refuses any
other, a lock update fails at that check until you change the expected
value. Compare the verification identity above instead, and record the
version. If you need the exact package bytes, pin `== 0.5.0` and keep the
checksum from `mix.lock`.

## Runtimes that cannot verify ML-DSA

A runtime linked against OpenSSL older than 3.5 verifies Ed25519 artifacts and
returns `:algorithm_unsupported_on_substrate` for ML-DSA artifacts instead of
a verdict: the signature is neither accepted nor rejected. To get the same answer on every machine, pass a
profile that admits only what the runtime can verify; when the runtime is
upgraded, widen the profile. [Integrate CAP into an application](integration.md)
shows both.
