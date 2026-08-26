# Recipes

End-to-end integration patterns using only the public facade
(`CharterAgreementProtocol`). Every recipe follows the same shape: caller
supplies bytes, time, limits, and keys; CAP returns facts or typed value-free
errors; your host owns every decision.

Throughout, `limits` is `CharterAgreementProtocol.Limits.default()` or your
own bounded values, and `alias CharterAgreementProtocol, as: CAP`.

## Verify a complete charter view you received

You hold raw artifacts from a counterparty and need the structural truth
before acting on anything.

```elixir
{:ok, chain_facts} =
  CAP.verify_chain(revision_bytes, acceptance_compacts,
                   descriptor_compacts, termination_compacts, limits)

case CAP.governing_revision(chain_facts, at) do
  {:ok, digest}      -> # unique governing revision at `at`
  {:ok, :contested}  -> # fork evidence retained; do not act unilaterally
  {:ok, :none}       -> # nothing effective at `at`
  {:error, error}    -> # typed, value-free failure — safe to log
end
```

`verify_chain/5` re-decodes and re-verifies every artifact from bytes — never
trust artifact-internal routing claims. If you only hold one descriptor
history, `CAP.verify_descriptor_chain/2` returns its topology (`:linear` or
`:forked`) with per-descriptor positions and signed sibling-fork evidence.

## Compose and sign an agreement receipt

The issuer just acted under the charter and must bind the action to the
agreement state that governed it.

```elixir
claims = %{
  "protocol_revision" => 1,
  "charter_id" => charter_id,
  "revision_number" => 2,
  "revision_digest" => revision_digest,
  "issuing_party_role" => "issuer",
  "agent_party_role" => "issuer",
  "deployment_digest" => abp_deployment_digest,
  "grant" => %{"scheme" => "bap", "id" => grant_id,
               "grant_digest" => "sha-256:" <> ath},
  "invocation_id" => invocation_id,
  "decision" => "accepted",
  "outcome" => "effect_committed",
  "occurred_at" => "2026-08-25T12:00:01Z",
  "recorded_at" => "2026-08-25T12:00:02Z",
  "extensions" => %{"critical" => %{}, "optional" => %{}}
}

{:ok, signing_input} = CAP.receipt_signing_input(%{"kid" => kid, "claims" => claims})

# Outside CAP, with your key custody:
signature = :crypto.sign(:eddsa, :none, signing_input.message, [private_key, :ed25519])

{:ok, compact} = CAP.assemble_compact(signing_input, signature)

# Post-verify before returning the compact to service:
{:ok, receipt_facts} = CAP.verify_receipt(compact, chain_facts, limits)
```

The grant digest composition (`"sha-256:" <> ath`) and the closed
decision/outcome pairs are specified in [Receipts](receipts.md). Governance is
recomputed at `occurred_at`; inside an unresolved fork the same receipt
verifies with `governing_match: :undetermined` — evidence, not adjudication.

## Rotate a party signing key

Key rotation is a descriptor successor, not a side channel:

```elixir
claims = %{
  "protocol_revision" => 1,
  "party_id" => party_id,                    # the genesis descriptor digest
  "prev_descriptor_digest" => current_digest,
  "descriptor_number" => current_number + 1,
  "verification_keys" => [
    %{"key_id" => "issuer-key", "algorithm" => "Ed25519",
      "public_key" => new_public_b64url, "status" => "active"},
    %{"key_id" => "issuer-key-rotated-out", "algorithm" => "Ed25519",
      "public_key" => old_public_b64url, "status" => "retired"}
  ],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-08-26T00:00:00Z"
}

{:ok, signing_input} = CAP.descriptor_signing_input(%{"kid" => "issuer-key", "claims" => claims})
# Sign with a key active in the PREDECESSOR; assemble; then verify:
{:ok, successor_facts} = CAP.verify_descriptor(compact, predecessor_facts, limits)
```

The successor must be signed by a key active in the predecessor — predecessor
facts you supply are reverified, never trusted, so they cannot bypass the
transition check. Consumers pinning the old descriptor learn of the rotation by
receiving the successor and re-verifying the chain.

## Detect and repair a contested fork

When `governing_revision/2` returns `:contested`, two accepted branches are
eligible. The only no-tie-break repair is a later revision, countersigned by
both parties, naming **each** contested sibling in `supersedes`:

```elixir
repair_claims = %{
  "revision_number" => 3,
  "charter_id" => charter_id,
  "prev_revision_digest" => left_digest,
  "supersedes" => Enum.sort([left_digest, right_digest]),
  # ...parties, legal_text, precedence_declaration, effective_from, ...
}

# Both parties run acceptance_signing_input/2 against the repaired set —
# the producer refuses ancestry that excludes any maximum dual-accepted head,
# so honest signers cannot accidentally deepen the fork.
```

The [fork-repair notebook](../notebooks/fork-repair.livemd) and
`mix run examples/supplier_fork_demo.exs` walk the complete sequence with real
signatures — equivocation evidence, contested view, countersigned repair,
unique governing digest.

## Handle verification failures at the call boundary

```elixir
case CAP.decode_charter_revision(bytes, limits) do
  {:ok, revision}     -> ...
  {:error, %CharterAgreementProtocol.Error{code: code, subject: subject}} ->
    Logger.warning("revision rejected: #{inspect(code)} at #{inspect(subject)}")
end
```

`code` is from a closed vocabulary and `subject` contains only protocol-owned
names and indexes — rejected values never appear, so error logs are safe by
construction. Match on the codes you treat specially (for example
`:signature_invalid`, `:extension_unknown_critical`, `:limit_exceeded`) and
route the rest to your audit surface. The complete code set is visible in
`CharterAgreementProtocol.Error`; per-code coverage — 19 corpus-exercised
codes with certified cases, the remainder exercised by in-repo tests or
declared-only — is tabulated in the [error-code reference](error-codes.md).

## Run the certified corpus in your CI

From a repository checkout (or an unpacked package directory):

```console
$ mix conformance.verify
```

From a dependent project, without leaving your application's Mix context:

```console
$ mix run -e 'CharterAgreementProtocol.Conformance.Cli.run(["--corpus", "deps/charter_agreement_protocol/priv/conformance"])'
```

The escript form also works from a checkout or unpacked package directory:

```console
$ mix escript.build && ./charter_agreement_protocol --corpus priv/conformance
```

Exit `0` proves all 85 certified cases recomputed and agreed. The CLI refuses
any corpus whose raw index identity is not the certified release pin, so a
tampered or self-consistently-regenerated corpus fails loudly. See
[Conformance](conformance.md).
