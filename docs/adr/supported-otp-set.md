# Supported toolchain: Elixir range, OTP set, and lockstep

Date: 2026-09-16

## Status

Accepted. Governs the development and CI toolchain declaration, not the wire
surface (`lib/` is untouched by this act). Backed by the build-existence and
capability probes recorded below (executed 2026-09-16) and by the sibling
signer audit (`charter_agreement_signer` v0.3.3, which landed the same range
and set); the two repositories are aligned by owner direction.

## Context

Before this act the toolchain identity lived outside the repository: no
`.tool-versions`, no `config/`, and the only floor declaration was the CI
matrix. A checkout built with any locally available Elixir/OTP combination
that happened to compile, silently. The 0.3.1 floor statement (OTP ≥ 28.1
with a linked OpenSSL ≥ 3.5) named the ML-DSA runtime axis but no supported
set of OTP majors, and the Elixir requirement `~> 1.20` lagged the family:
the signer sibling had proven (and shipped, v0.3.3) that CAP compiles and its
battery runs on 1.19.x, making the stricter declared floor metadata that did
not match tested reality — and Mix does not enforce a dependency's `:elixir`
requirement, so consumers on 1.19.x already compiled CAP regardless.

Probes (2026-09-16):

- Build existence: stable precompiled 1.20.x builds exist for exactly OTP
  27, 28, and 29 (asdf/bob `builds.txt` and the docker official tag list
  agree). OTP 26 only ever carried 1.20.0 release-candidate builds, and
  Elixir v1.20.3's own Makefile refuses to build on OTP < 27; no OTP 30
  builds exist anywhere. The 1.19.x line (1.19.4–1.19.6) carries otp-26/27/28
  builds only.
- Capability (decisive for OTP 27): on OTP 27.3.4.17 with OpenSSL 3.5.5
  confirmed linked (docker `hexpm/elixir:1.20.4-erlang-27.3.4.17-ubuntu-resolute`,
  `--platform linux/amd64`), `:crypto.supports(:public_keys)` returns
  `[:rsa, :dss, :dh, :ec_gf2m, :ecdsa, :ecdh, :eddsa, :eddh, :srp]` — none of
  `:mldsa44/65/87`. `Signature.verify_ml_dsa/4` fail-closes without those
  atoms, so the revision-3 conformance corpus cannot pass on OTP 27 at any
  OpenSSL version. (This corrects the signer audit session's recorded claim
  that ML-DSA capability exists on OTP 27; the signer's {28, 29} conclusion
  was right, for this stronger reason.)
- Floor lane (widened admission): Elixir 1.19.5 on OTP 28.5.0.3, runtime
  linked against OpenSSL 3.6.3 — compile green, the certified conformance
  corpus recomputes to the recorded index
  (`SQYrs8WyUX4Bj_QlupjB_KYaMyjVjrnwvQ79sNkyIao`), and the full suite passes
  (3 properties, 265 tests, 0 failures).
- Refusals: Elixir 1.18.4 refuses with Mix's
  `Mix.ElixirVersionError` (`... supports only Elixir ~> 1.19`) before
  anything compiles; a 1.20.2 build on OTP 27 refuses with the
  `config/config.exs` assert (`charter_agreement_protocol supports
  Erlang/OTP 28/29; running 27 ...`).

## Decisions

1. **Elixir range `~> 1.19`.** The tested lines are 1.19.x and 1.20.x; `~> 1.19`
   means `< 2.0.0`, so each new Elixir minor is admitted by the requirement
   and becomes supported only when a lane proves it. Anything below 1.19.0
   (1.18.x today) is refused by Mix before compilation. Aligned with the
   signer sibling. Known boundary: 1.18 is additionally blocked by
   compile-time behavior in `extension_registry.ex` — the module holds
   compiled `~r` regular expressions in module attributes (`@tagged_digest`,
   and the match constraints carried inside `@profiles`), and Elixir 1.18's
   compile-time escape cannot serialize the `#Reference` a compiled `Regex`
   carries (1.19+ can). Outside today's range and therefore not a defect
   until the range moves; the widening slice must lift it (for example by
   binding source patterns and compiling at runtime) — recorded here so the
   family's 1.18 widening starts from the mechanism, not a symptom.
2. **Supported OTP set {28, 29}.** Build existence alone would admit 27; the
   ML-DSA capability probe excludes it — a supported major must carry the
   complete quality battery, and the revision-3 corpus fail-closes on 27.
   The ML-DSA runtime floor (OTP ≥ 28.1 with a linked OpenSSL ≥ 3.5,
   per the ML-DSA admission ADR) is unchanged and is the reason 28 carries
   the floor lane.
3. **In-repo enforcement.** `config/config.exs` asserts the running OTP major
   against the set before anything compiles
   (`to_string(:erlang.system_info(:otp_release))` — the release arrives as a
   charlist and a bare comparison always fails). The config directory is
   development/CI state and does not ship in the Hex package; consumers are
   governed by the declared floors in the README, not by this assert.
4. **Lockstep.** The `mix.exs` `:elixir` range, `config/config.exs`'s
   supported set, `.tool-versions`, and the CI matrix lanes move together in
   ONE commit. A lane outside the declared set, or a supported major with no
   lane, is a defect. Current lanes: pinned `1.20.3`/`29.0.3` (mirrors
   `.tool-versions` and the dev toolchain) and floor `1.19.5`/`28.5.0.3`
   (mirrors the signer's floor lane), both on ubuntu-26.04 for the ML-DSA
   substrate.
5. **A fresh clone must build on Windows.** CI carries a
   `windows-build` lane proving the clone bar — checkout, `deps.get`,
   test-environment compile with warnings-as-errors, format check, and the
   dependency-currency gate — on the official Erlang/OTP Windows builds of
   OTP 29 with the Elixir 1.20.3 precompiled archive, and `.gitattributes`
   pins LF / binary treatment for the byte-exact corpus, fixtures, and pins
   so `core.autocrlf` cannot corrupt a Windows checkout. The declared gates
   contain no POSIX-shell dependency (the currency gate is an Elixir script
   spawning `mix` through `cmd /c` on Windows). The full test suite on
   Windows is deliberately not claimed: the revision-3 ML-DSA corpus needs
   the runtime's linked OpenSSL ≥ 3.5, and the official Windows OTP
   binaries' bundled OpenSSL version is not a declared fact; extending the
   lane to `mix test` is gated on that fact.
