# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.3.x | yes |
| 0.1.x – 0.2.x | verification only |

## Reporting a vulnerability

Use GitHub private vulnerability reporting for
`baselabs/charter_agreement_protocol`. Do not open a public issue containing
an exploit, credential, private key, production data, tenant data, or
unreleased vulnerability detail.

A report should identify the affected commit or package version, the violated
property, a minimal value-free reproduction, and the expected fail-closed
result.

## Security boundary

The package is a pure verification library: it decodes and verifies signed
charter evidence (Ed25519 and, from `protocol_revision` 3, ML-DSA) and never
signs, authorizes, reads a clock, or performs I/O. The full proves / never-proves
boundary is documented in the shipped security model
(`docs/guides/security-model.md`) and the normative security considerations
(`spec/security-considerations.md`).
