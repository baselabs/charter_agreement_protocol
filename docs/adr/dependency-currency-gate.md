# Dependency currency: latest-first policy and the currency gate

Date: 2026-09-16

## Status

Accepted. Governs dependency hygiene for development/test-only dependencies
(CAP has zero runtime dependencies; every Mix dep is `runtime: false`).
Backed by the gate proofs recorded below (executed 2026-09-16) and sharing
scars with the sibling signer audit's currency gate.

## Context

Dependencies drifted silently: `mix hex.outdated` could sit un-run for
release after release, anything resolver-updatable stayed un-updated without
a recorded reason, and nothing in the battery noticed. The failure modes
that shaped this gate (each observed in the family's audits):

- `mix hex.outdated` exits nonzero both on drift and on a failed hex.pm
  lookup — an exit-code check cannot tell "stale" from "unverified".
- The rendered result table pads rows with trailing whitespace — status
  patterns anchored on a bare `$` fail open.
- A currency script with an internal `cd` to the repo root made a
  per-project CI job gate the wrong project — the gate must run in the
  caller's working directory.
- `mix format` does not enforce the `:elixir` requirement; toolchain refusal
  proofs must use `mix compile`.

## Decisions

1. **Latest-first.** Everything `mix hex.outdated --all` marks "Update
   possible" is updated in the change that notices it. A dependency not at
   latest is a deliberate pin carrying an inline reason in `mix.exs`.
   Current pins: `agent_blueprint_protocol == 0.1.1` and
   `bounded_authority_protocol == 0.1.2` — exact identity contracts with the
   charter-family siblings the fixture and conformance battery is certified
   against; their 0.1 → 0.7 / 0.1 → 0.4 breaking-family jumps are deliberate
   slices of their own, never a currency rider.
2. **The gate.** `scripts/check_currency.exs` (invoked as `mix
   currency.check`) runs in the caller's working directory — the script never
   changes directories; classifies exclusively on the rendered
   `mix hex.outdated --all` table with status matches anchored on `\s*$`;
   exits nonzero naming every resolvable-drift row; prints each
   resolver-rejected package's requirement chain (`mix hex.outdated <pkg>`)
   so pins stay auditable against their inline reasons; and exits nonzero
   with "currency unverified" when no table renders — a failed hex.pm lookup
   (or a missing lock manifest) can never pass as green. It is an Elixir
   script that spawns `mix` through `cmd /c` on Windows, so no POSIX shell
   is required on any host and the gate runs identically on every CI lane.
3. **Wiring.** The gate runs inside `mix quality` as `currency.check`
   (ordered after `deps.audit`; the architecture test
   `ReleaseGateTest` pins the exact alias composition) and as its own
   explicit CI step before the battery, so resolvable drift surfaces as a
   named failure rather than a line inside gate output. `mix hex.audit`
   already runs first inside the same battery, keeping the CVE discipline on
   every lane and after every dependency move.
4. **Proofs (2026-09-16).** Green on the current lock (exit 0, no drift
   rows); red on a fabricated drift (lock reverted to dialyxir 1.4.7 in a
   scratch copy, `deps.get`, exit 1 naming `dialyxir` with its row); red on
   the no-table path — an isolated `HEX_HOME` with no cache and an
   unreachable `HEX_MIRROR`, i.e. a genuine failed hex.pm lookup: exit 1,
   "currency unverified … no result table". A removed `mix.lock` fails
   closed one level earlier, at Mix's own dependency check, before the gate
   even runs — also never green.
