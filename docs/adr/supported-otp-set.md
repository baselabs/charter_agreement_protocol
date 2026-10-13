# Supported toolchain: Elixir range, OTP set, and lockstep

Date: September 16, 2026

## Status

Accepted. Governs the development and CI toolchain declaration, not the wire format.
It rests on the build and capability findings below, and matches the signer package
(`charter_agreement_signer`), which uses the same range and set.

Amended September 26, 2026: the macOS and Windows CI jobs this record originally
required were withdrawn. CI runs on Linux only. Developers work on macOS or Linux, and
Windows developers use WSL2, which is the Linux path.

## Context

Before this decision the toolchain identity lived outside the repository. There was
no `.tool-versions`, no `config/`, and the only floor declaration was the CI matrix. A
checkout built with whatever Elixir and OTP happened to be installed and compiled,
with no warning. The 0.3.1 floor statement (OTP 28.1 or later with OpenSSL 3.5 or
later linked) named the ML-DSA runtime requirement but no supported set of OTP major
versions. The Elixir requirement `~> 1.20` was also stricter than reality: the signer
package had shown (and shipped in v0.3.3) that CAP compiles and its full check suite
runs on 1.19.x. Mix does not enforce a dependency's `:elixir` requirement, so
consumers on 1.19.x already compiled CAP anyway.

Findings (September 16, 2026):

- Builds. Stable precompiled Elixir 1.20.x builds exist for OTP 27, 28 and 29, and
  the 1.19.x line has builds for OTP 26, 27 and 28. Elixir 1.20 does not build on OTP
  below 27, and no OTP 30 builds exist.
- ML-DSA on OTP 27. OTP 27 does not offer ML-DSA in `:crypto`, even when linked
  against OpenSSL 3.5, so the revision-3 conformance cases cannot pass on OTP 27.
- The floor. Elixir 1.19.5 on OTP 28.5, linked against OpenSSL 3.5 or later,
  compiles CAP and passes the full test suite and the conformance corpus.
- Refusals. In this repository, Mix refuses Elixir 1.18 before anything compiles,
  because of the `~> 1.19` requirement, and `config/config.exs` refuses OTP 27.

## Decisions

1. **Elixir range `~> 1.19`.** The tested lines are 1.19.x and 1.20.x. `~> 1.19` means
   below 2.0.0, so each new Elixir minor release is allowed by the requirement and
   becomes supported only when a CI job proves it. Anything below 1.19.0 (1.18.x
   today) is refused by Mix before compiling. This matches the signer package. One
   known boundary: 1.18 is also blocked by compile-time behavior in
   `extension_registry.ex`. The module holds compiled `~r` regular expressions in
   module attributes (`@tagged_digest`, and the match constraints inside `@profiles`),
   and Elixir 1.18's compile-time escape cannot serialize the `#Reference` a compiled
   `Regex` carries (1.19 and later can). That is outside today's range, so it is not a
   defect until the range moves. The change that widens the range to 1.18 must remove
   it, for example by keeping source patterns and compiling them at runtime. It is
   recorded here so that work starts from the cause, not a symptom.
2. **Supported OTP set {28, 29}.** Build existence alone would allow 27. The ML-DSA
   capability probe rules it out: a supported major version must pass the full check
   suite, and the revision-3 corpus fails closed on 27. The ML-DSA runtime floor (OTP
   28.1 or later with OpenSSL 3.5 or later linked, from the ML-DSA admission record) is
   unchanged, and it is why 28 carries the floor CI job.
3. **Enforced in the repository.** `config/config.exs` checks the running OTP major
   version against the set before anything compiles
   (`to_string(:erlang.system_info(:otp_release))`; the release arrives as a charlist,
   and a bare comparison always fails). The config directory is development and CI
   state and does not ship in the Hex package. Consumers are governed by the floors
   declared in the README, not by this check.
4. **Lockstep.** The `mix.exs` `:elixir` range, the supported set in
   `config/config.exs`, `.tool-versions` and the CI matrix move together in one commit.
   A CI job outside the declared set, or a supported major version with no CI job, is a
   defect. The full-quality CI matrix has two jobs: pinned `1.20.3`/`29.0.3` (matching
   `.tool-versions` and the development toolchain) and floor `1.19.5`/`28.5.0.3`
   (matching the signer's floor job), both on ubuntu-26.04 for its OpenSSL 3.5. A
   separate capability-limited job runs on Ubuntu 24.04 (Elixir 1.20.3, OTP 28.5.0.3,
   OpenSSL 3.0) to check behavior on a runtime without ML-DSA, and two more jobs
   check workflow syntax and scan for secrets.
5. **Developer platforms.** Developers work on macOS or Linux, and Windows developers
   use WSL2. Developer portability is proven on a developer machine, not by a CI job.
   `.gitattributes` pins LF line endings and binary treatment for the byte-exact
   corpus, fixtures and pins, so line-ending conversion cannot corrupt a checkout.
