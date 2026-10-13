# Pre-sign check

Date: October 13, 2026. Status: accepted.

CAP owns the checks that precede external signing and the context used to
verify the result. `prepare_signing/5` returns `SigningPlan` and
`finish_signing/2` assembles and verifies the external signature. The holder
passes a snapshot public key; CAP compares it with its internal candidate
keys. This keeps same-kid receipt candidates intact without exposing a key
list. Each public verifier and preparation share one internal pipeline.

Four public checks mirroring the verifiers would leave context derivation
in each signer and expose too much API. A check over an already-built
signing input would inherit the old producer's default limits. Adding
producer and assembler arities would enlarge the surface and risk changing
existing callers. Skipping final verification would lose the public
verifier check over the result. The selected pair of calls keeps the old
arities and bytes stable, carries caller limits through assembly, and keeps
the context in CAP.

CAP Elixir 0.6.0 adds API and corpus coverage. Its verification semantics
moves to 6 because Ed25519 admission rejects two more small-order encodings
and keys that are not curve points, and malformed caller-built context
field types now return `invalid_type` consistently on existing verification
surfaces. The point rule applies to both the public key and signature `R`. The 0.6.0
compatibility row records accepted-to-error, crash-to-error and error-code
transitions; the historical wire corpora keep their verdicts.
