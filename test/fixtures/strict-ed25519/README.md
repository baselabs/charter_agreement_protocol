# Strict Ed25519 test fixtures

Source: [baselabs/bounded_authority_protocol](https://github.com/baselabs/bounded_authority_protocol),
package version 0.8.0, `priv/conformance/strict-ed25519`. License: Apache-2.0.
The Taming cases retain their upstream Apache-2.0 provenance in the file.

These 12 case files are byte-for-byte copies of the primitive, taming,
differential and acceptable-public-key files. `hashes.json` records their
SHA-256 hashes and counts from the source index in one place.

The 1,300 cases use `ed25519.verify_strict` or
`ed25519.acceptable_public_key`. Inputs are unpadded base64url bytes, and
`expected.verdict` is `valid` or `invalid`, as described by the source
`profile.json`. The torsion-free host surface is excluded.

These files are CAP test fixtures only. They are outside CAP's conformance
corpus, specification and package file list.
