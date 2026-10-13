# Dependency currency: latest first, and the currency check

Date: September 16, 2026

## Status

Accepted. Governs dependency hygiene for the development and test dependencies. CAP
has no runtime dependencies; every Mix dependency is `runtime: false`. The companion
signer package uses the same check.

## Context

Dependencies drifted without anyone noticing. `mix hex.outdated` could go unrun for
several releases, packages that could be updated stayed behind without a recorded
reason, and no check caught it. These failure modes shaped the check:

- `mix hex.outdated` exits nonzero both when something is out of date and when the
  hex.pm lookup fails, so an exit-code check cannot tell "stale" from "unknown".
- The rendered result table pads rows with trailing whitespace, so status patterns
  anchored on a bare `$` never match and the check passes when it should fail.
- A currency script that changed into the repository root made a per-project CI job
  check the wrong project. The check must run in the caller's working directory.
- `mix format` does not enforce the `:elixir` requirement. Proofs that a toolchain is
  refused must use `mix compile`.

## Decisions

1. **Latest first.** Everything `mix hex.outdated --all` marks "Update possible" is
   updated in the change that notices it. A dependency that is not at its latest
   version is a deliberate pin with an inline reason in `mix.exs`. Current pins:
   `agent_blueprint_protocol == 0.1.1` and `bounded_authority_protocol == 0.1.2`.
   These are exact identity contracts with the sibling protocols that CAP's fixtures
   and conformance tests are checked against. Their jumps to newer major lines
   (0.1 to 0.7, and 0.1 to 0.4) are separate pieces of work, never part of a currency
   update.
2. **The check.** `scripts/check_currency.exs`, run as `mix currency.check`:
   - runs in the caller's working directory and never changes directory;
   - classifies only from the rendered `mix hex.outdated --all` table, with status
     matches anchored on `\s*$`;
   - exits nonzero and names every row that could be updated;
   - prints each resolver-rejected package's requirement chain
     (`mix hex.outdated <pkg>`), so pins can be compared with their inline reasons;
   - exits nonzero with "currency unverified" when no table renders, so a failed
     hex.pm lookup or a missing lock file can never pass.

   It is an Elixir script, so it needs no POSIX shell.
3. **Wiring.** The check runs inside `mix quality` as `currency.check`, after
   `deps.audit` (the architecture test `ReleaseGateTest` pins the exact alias list),
   and as its own CI step before the rest of the checks, so drift shows up as a named
   failure rather than a line inside other output. `mix hex.audit` already runs first
   in the same list, so known vulnerabilities are checked on every run and after every
   dependency change.
4. **What the check catches.** It passes on a current lock with no drift rows. It
   fails, naming each row, when a dependency could be updated. It fails with
   "currency unverified ... no result table" when the hex.pm lookup fails. A missing
   `mix.lock` fails earlier, at Mix's own dependency check.
