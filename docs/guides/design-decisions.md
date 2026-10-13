# Design decisions

CAP records each significant design decision as a decision record (ADR). This page
gives one line per record: what was decided, and what it means when you use CAP.

| Decision | What it means for you |
|---|---|
| [No version tokens in identifiers](../adr/no-versioning-rule.md) | Versions live in the artifacts (`protocol_revision`) and in the package version, never in module, function or path names, so an upgrade does not rename the API you call. |
| [Conformance and the release candidate](../adr/conformance-release-candidate.md) | Each release pins its conformance corpus, extension registry and specification by digest, so you can confirm the corpus you test against is the one that shipped. |
| [Algorithm-name agility](../adr/algorithm-name-agility.md) | New artifacts are signed as `Ed25519` at protocol revision 2, older `EdDSA` artifacts at revision 1 keep verifying, and one charter can mix both. |
| [ML-DSA admission](../adr/ml-dsa-admission.md) | ML-DSA (post-quantum) signatures verify from protocol revision 3. All three sizes are accepted, producers mint ML-DSA-65, and a party can move from Ed25519 to ML-DSA keys within one descriptor history. |
| [Release identity](../adr/release-identity.md) | To check stored results after an upgrade, compare the verification semantics number, your limits and the signature registry digest, not the package version. `capabilities/0` reports what your runtime can verify, and `Capability.Profile` narrows what you accept. |
| [Supported toolchain](https://github.com/baselabs/charter_agreement_protocol/blob/main/docs/adr/supported-otp-set.md) | CAP requires Elixir `~> 1.19`, tested on 1.19 and 1.20, on OTP 28 or 29. Verifying ML-DSA also needs OTP linked against OpenSSL 3.5 or later. |
| [Dependency currency](https://github.com/baselabs/charter_agreement_protocol/blob/main/docs/adr/dependency-currency-gate.md) | CAP has no runtime dependencies. Its development dependencies stay at their latest versions unless pinned with a stated reason. |

The last two records are about how the repository is built and tested, so they are
kept in the repository rather than in these docs.
