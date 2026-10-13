# Contributing

CAP is a verification protocol, so most changes touch its contract: what a
verifier accepts, what it rejects and what it reports. This guide covers how
to set up, what `mix quality` checks, how the pinned TypeScript verifier
works, how to change the corpus or the specification, and what every change
needs before it lands.

## Setup

You need:

- **Elixir `~> 1.19`.** CI tests 1.19.5 and 1.20.3; `.tool-versions` pins
  Elixir 1.20.3 on OTP 29.
- **Erlang/OTP 28 or 29**, 28.1 or newer. `config/config.exs` refuses any
  other major version before compiling. It checks only the major, so make
  sure a 28 install is 28.1 or later: ML-DSA support in `:crypto` starts
  there.
- **OpenSSL 3.5 or newer linked into OTP's `:crypto`.** OTP exposes ML-DSA
  only when its libcrypto is 3.5 or later, and the conformance corpus
  contains ML-DSA cases. With an older OpenSSL, the ML-DSA cases fail.
- **Node 24.8 or newer**, for the checks that run the TypeScript verifier.
  `mix verifier.agreement` checks only for major version 24, so check the
  minor yourself.
- **git with full history and tags.** `mix historical.check` reads the
  corpora of earlier releases from their tags, so a shallow clone fails.
- **Network access** the first time you run the tests: they fetch the
  pinned TypeScript verifier source from GitHub (see below).

macOS and Linux are supported. On Windows, use WSL2.

Check that your runtime can verify every registered algorithm:

```console
$ mix deps.get
$ mix run --no-start -e 'for r <- CharterAgreementProtocol.capabilities().algorithms, do: IO.puts("#{r.name} #{r.verifiable}")'
EdDSA true
Ed25519 true
ML-DSA-44 true
ML-DSA-65 true
ML-DSA-87 true
```

A `false` row means this runtime could not verify that algorithm's pinned
test vector: the runtime does not offer the algorithm, or it offers it but the
check fails. For ML-DSA, check which crypto library OTP links
(`:crypto.info_lib/0`, which needs OpenSSL 3.5 or later) and whether its
provider is enabled.

The Elixir range in `mix.exs`, the supported OTP set in `config/config.exs`,
`.tool-versions` and the CI matrix change together, in one commit. The
reasons are in the
[supported-toolchain design record](https://github.com/baselabs/charter_agreement_protocol/blob/main/docs/adr/supported-otp-set.md)
and the
[dependency-currency design record](https://github.com/baselabs/charter_agreement_protocol/blob/main/docs/adr/dependency-currency-gate.md).

## Running the checks

```console
$ mix test        # the test suite; builds the TypeScript verifier source if needed
$ mix quality     # everything CI runs, in CI's order
```

`mix quality` runs these steps in order and stops at the first failure.
`test/architecture/release_gate_test.exs` asserts this exact list, so a
change to the alias in `mix.exs` changes that test too.

| Step | What it proves |
| --- | --- |
| `hex.audit` | no dependency is a retired Hex release |
| `deps.unlock --check-unused` | the lock file holds no unused entries |
| `deps.audit` | no dependency has a known security advisory |
| `currency.check` | every dependency is on its latest resolvable version |
| `format --check-formatted` | the code is formatted |
| `compile --warnings-as-errors` | the code compiles with no warnings |
| `credo --strict` | the code passes the strict lint rules |
| `verifier.source` | `_build/verifier-source/` holds the pinned TypeScript verifier commit |
| `test --cover --seed 42` | the suite passes with 100% coverage (test fixtures and the CLI excluded) |
| `conformance.verify` | the corpus passes, regenerates byte for byte, and `spec/requirements.md` matches the requirement map |
| `historical.check` | every earlier release's corpus gives the same verdicts today, except listed, deliberate changes |
| `conformance.mutations` | each named source mutation makes a test fail (see below) |
| `verifier.agreement` | the Elixir and TypeScript verifiers produce byte-identical reports on the repository corpus and on the corpus inside a built package |
| `differential.check` | both JSON decoders give identical results on freshly generated inputs |
| `dialyzer` | the type specs are consistent |
| `docs --warnings-as-errors` | the HexDocs build has no warnings: references to modules, functions and local pages resolve. It does not fetch external URLs or run examples; the doctests and `test/docs` run examples |
| `release.candidate` | the package contents, release metadata and identity pins match the live code (see the [release runbook](https://github.com/baselabs/charter_agreement_protocol/blob/main/docs/release-runbook.md)) |

`verifier.agreement` and `differential.check` also run a deliberately broken
copy of the TypeScript source and require the comparison to fail, so a
comparison that can never fail is caught.

CI runs `mix quality` on Linux with two toolchains: Elixir 1.20.3 on OTP
29.0.3 with Node 24, and Elixir 1.19.5 on OTP 28.5 with Node 24.8. CI skips
pushes that change only Markdown files or `docs/`, so run `mix quality`
locally before pushing a documentation change.

## The pinned TypeScript verifier

The second implementation lives in its own repository,
[charter_agreement_protocol_typescript](https://github.com/baselabs/charter_agreement_protocol_typescript),
and the npm package `@charter-agreement-protocol/verifier` is built from it.
`priv/verifier-source.json` names the repository and the exact commit this
repository's cross-implementation checks run against:

```json
{"commit":"<40-character SHA>","repository":"https://github.com/baselabs/charter_agreement_protocol_typescript.git"}
```

`mix verifier.source` fetches that commit and extracts it into
`_build/verifier-source/`. It refuses the pin unless:

- the commit is on the TypeScript repository's `main` branch as fetched from
  GitHub (a commit only in a local checkout is not enough, because CI cannot
  see it);
- the newest pin change moves forward: the pin descends from the newest
  committed pin, and that one from the pin before it on the first-parent
  history, so a committed backward pin fails in its own CI run and a later
  forward commit repairs it (this needs a full clone);
- every extracted file matches the pinned commit's tree.

`mix verifier.source --cached` skips the fetch and uses the local cache. A
checkout at `../charter_agreement_protocol_typescript` supplies objects
when present. Every check that runs the TypeScript code refuses a tree built
from a different pin.

The file ships in the Hex package, so anyone can tie this release to the
TypeScript source it was checked against. The TypeScript source itself does
not ship.

## Changing the corpus or the specification

A corpus, registry or specification change moves the identities that
`priv/release-metadata.json`, the CLI, the TypeScript verifier and the docs
pin. The [release runbook](https://github.com/baselabs/charter_agreement_protocol/blob/main/docs/release-runbook.md)
lists every step in order. In short:

1. Change the generator (`scripts/generate_conformance_corpus.exs`) and run
   it. Never edit case files by hand: `mix conformance.verify` regenerates
   the corpus and fails if a byte differs.
2. Update `RequirementMap` and render `spec/requirements.md`.
3. Run `mix run scripts/record_conformance_identity.exs`. It records the
   CLI and package-test index SHA-256, the latest compatibility row's corpus
   digest, and the guide's identity table from the live corpus and spec.
4. Update the compatibility row in `release_identity.ex`. A verdict change
   raises the verification semantics version and lists the transition.
5. Move the TypeScript pin: update the TypeScript repository's vendored
   corpus and the two identity constants in its `core.ts`, push to its
   `main`, set the new commit in `priv/verifier-source.json`, run
   `mix verifier.source`, and update the `certified-index-drift` entry in
   `scripts/check_verifier_agreement.exs`.
6. Update the identity table in
   [docs/guides/conformance.md](docs/guides/conformance.md).
7. Last, run `mix run --no-start scripts/record_release_metadata.exs`. It
   rewrites the metadata and the content pin, and the content pin covers
   every shipped file. Any later edit to a shipped file, including a guide,
   means running it again.

A change to `spec/` also needs an entry in `spec/changelog.md`.

## Source mutations

`scripts/check_conformance_mutations.exs` holds a list of named mutations.
Each one replaces one exact line in `lib/` with a broken version, in a
scratch copy of the repository, and names the test command that must then
fail. The script first checks that the command passes on the unmodified
copy, so a mutation only counts when the failure comes from the change. The
live tree is never modified.

To add one:

1. Add an entry with `name`, `path`, `from`, `to` and `command`. The `from`
   text must occur exactly once in the file, and `to` must differ from it;
   `scripts/seeded_mutation.exs` enforces both.
2. Add the name to `@mutation_names` in
   `test/architecture/release_gate_test.exs`.
3. Bind it to the requirement it protects in
   `lib/charter_agreement_protocol/requirement_map.ex` and render
   `spec/requirements.md`. `mix conformance.verify` fails if a mutation is
   bound to no requirement.

The [requirements matrix](spec/requirements.md) shows which mutation guards
each requirement.

## What every change needs

- **A test you have seen fail.** Every behavior change and every new check
  arrives with a test that fails without the change, for the reason the
  change addresses.
- **A mutation for new verification behavior.** Add a named mutation that
  breaks the new check and prove a test catches it.
- **Docs in the same change.** New public behavior lands with its guide
  section, its CHANGELOG entry and its API docs. Every technical statement in
  the docs must trace to the code, the corpus or a cited source.
- **Notebooks that still run.** If you change an API a notebook uses, run the
  notebook top to bottom before landing.

## Rules the code keeps, and the tests that hold them

The tests in `test/architecture/` enforce these rules. A change that breaks
one fails `mix test`.

- **CAP never authorizes.** No production identifier uses authorization or
  term-evaluation vocabulary (`non_authorizing_vocabulary_test.exs`,
  `term_evaluation_vocabulary_test.exs`), and every module states its
  non-authorizing boundary in its docs (`public_contract_coverage_test.exs`).
- **No I/O in verification.** Production code uses only OTP `:crypto`.
  `runtime_purity_test.exs` scans the compiled modules and rejects
  filesystem, clock, calendar, shell and dynamic-dispatch calls everywhere
  except the conformance CLI, which reads corpus files. No module in `lib/`
  uses the network, environment variables or the process dictionary either,
  though no test checks for those. Callers supply time, limits and keys.
- **No production dependencies.** Every Mix dependency is `only: [:dev,
  :test]` with `runtime: false` (`runtime_purity_test.exs`,
  `dependency_direction_test.exs`).
- **No signing custody.** Production code builds signing inputs and
  assembles a signature the caller supplies, and never holds a key
  (`signing_boundary_test.exs`).
- **Every public function has a spec** (`public_contract_coverage_test.exs`).
- **Every facts struct is built through one constructor**, which always
  adds the twelve `not_verified` items (`facts_construction_test.exs`).
- **Errors carry no values.** Every error uses a declared code, and every
  declared code is emitted somewhere; details are fixed, protocol-owned
  literals, never rejected input (`error_vocabulary_test.exs`).
- **No version tokens in identifiers.** No `V2Decoder`, `priv/v1/`,
  `decode_v2`, or similar in any path, module, function, atom, struct key or
  test name. The Hex version and its `source_ref` tag are the only
  version-bearing identities (`identifier_naming_test.exs`; see the
  [versioning design record](docs/adr/no-versioning-rule.md)).
- **Every normative statement has a requirement ID.** Each sentence in
  `spec/core.md` with an uppercase keyword (MUST, SHOULD, MAY and the rest)
  carries a `CAP-...` identifier bound in the requirement map
  (`normative_spec_test.exs`).

## Package contents

The shipped archive is an explicit list in `mix.exs` (`package: [files:
...]`): the code, the conformance corpus, the release metadata, the verifier
pin and named documents. Tests, scripts and environment files never ship. If
you add a public document, add it to that list and to the docs `extras`;
`mix release.candidate` checks the unpacked archive's exact file list either
way.

## Working against a sibling repository

To try a local change in a dependency such as `agent_blueprint_protocol`,
point it at a local `path:` in your working tree. `mix quality` fails while
it is there: `mix release.candidate` reads the dependency list from the
working tree and rejects `path:` and `git:` dependencies. Switch it back
before running the full check or committing.

## Commits and pull requests

Changes land on `main`; open a pull request against it. Stage explicit
paths (not `git add .` or `-A`), and say what changed and why in the commit
body. `mix quality` passes on the exact tree you push.

## Security issues

Do not open a public issue. See [SECURITY.md](SECURITY.md).

## Releasing

The steps for cutting a release are in the
[release runbook](https://github.com/baselabs/charter_agreement_protocol/blob/main/docs/release-runbook.md).
