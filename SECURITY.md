# Security policy

## Supported versions

| Version | Security fixes |
| --- | --- |
| 0.6.x | yes, once released |
| 0.5.x and earlier | no; upgrade to 0.6.x once released |

0.5.0 fixes two verification defects. In 0.1.0 through 0.4.1, a charter in
which one party held both roles could verify. In 0.4.0 and 0.4.1, a narrowed
capability profile passed to `verify_acceptance/5`, `verify_termination/5` or
`verify_receipt/4` was not applied to the context those calls verify again.
The [changelog](CHANGELOG.md) describes both and how to check results you
stored under an earlier release.

The [upgrade guide](docs/guides/upgrading-verification-identity.md) lists
what changed between lines and what to record when you upgrade.

## Reporting a vulnerability

Report it privately through GitHub's private vulnerability reporting for
`baselabs/charter_agreement_protocol` (the repository's Security tab, then
"Report a vulnerability"). If that form is not available, open a public issue
that asks for a private contact and contains no details.

Never put an exploit, credential, private key, production data or an
unfixed vulnerability's details in a public issue, pull request or
discussion.

A useful report names:

- the package version or commit;
- the property that fails, for example "a modified artifact verifies" or "a
  limit is not enforced";
- the smallest reproduction you have, using test keys and synthetic data;
- the result you expected, which for CAP is usually a typed
  `{:error, %CharterAgreementProtocol.Error{}}`.

## What happens after you report

| Step | Target |
| --- | --- |
| We confirm we received the report | within 3 business days |
| We tell you whether we can reproduce it and how serious it is | within 10 business days |
| We ship a fix in a patch release | as soon as it is ready, within 90 days of the report |
| We publish an advisory crediting you (unless you ask us not to) | when the fix is on Hex |

If a fix needs longer than 90 days, we agree a new date with you before the
90 days run out. Please keep the details private until the advisory is
published.

## Scope

In scope: everything in the Hex package.

- The verification paths: decoding, canonicalization, digests, signature
  checks, chain and receipt verification, and the facts they return. The
  producer helpers (signing inputs and compact assembly) are in scope too.
  None of this code performs I/O: it reads no clock, file, network or
  environment, and the caller supplies time, limits and keys.
- The conformance CLI (`CharterAgreementProtocol.Conformance.Cli`), the one
  part of the package that reads files. It reads a corpus directory, caps
  itself at 64 files and 32 MiB, and rejects symlinks and any other entry
  that is not a regular file or a directory.
- The shipped conformance corpus and `priv/release-metadata.json`.

Out of scope here:

- What your application does with the facts. CAP verifies and never
  authorizes; the [security model](docs/guides/security-model.md) lists what
  stays with the host.
- Key custody: CAP never holds a key; the caller signs. Report signer
  issues to
  [charter_agreement_signer](https://github.com/baselabs/charter_agreement_signer).
- The TypeScript verifier: report to
  [charter_agreement_protocol_typescript](https://github.com/baselabs/charter_agreement_protocol_typescript).

The full statement of what CAP proves and never proves is in the
[security model](docs/guides/security-model.md) and the normative
[security considerations](spec/security-considerations.md).
