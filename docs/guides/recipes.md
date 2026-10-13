# Recipes

Short, working answers to the tasks an integration meets most often. Every
recipe calls the main module, `CharterAgreementProtocol`, and nothing else
from CAP's internals. Your code supplies the bytes, the time, the limits and
the keys. CAP returns verified facts or a typed error, and your application
decides what to do next.

All recipes start from the same setup: two parties and a charter both of them
accepted. Run the setup block first, then any recipe on its own. Every block on
this page runs in a test, both with the setup alone and in page order.

## Set up two parties and an accepted charter

```elixir
alias CharterAgreementProtocol, as: CAP
alias CharterAgreementProtocol.{Base64Url, Digest, Limits}

limits = Limits.default()

# Your key custody signs. Two in-memory Ed25519 keys stand in for it here.
{issuer_public, issuer_private} = :crypto.generate_key(:eddsa, :ed25519)
{acceptor_public, acceptor_private} = :crypto.generate_key(:eddsa, :ed25519)

sign = fn signing_input, private_key ->
  signature = :crypto.sign(:eddsa, :none, signing_input.message, [private_key, :ed25519])
  {:ok, compact} = CAP.assemble_compact(signing_input, signature)
  compact
end

# One genesis Party Descriptor per party, each listing the party's key.
descriptor = fn kid, public_key, private_key ->
  claims = %{
    "protocol_revision" => 2,
    "descriptor_number" => 1,
    "verification_keys" => [
      %{
        "key_id" => kid,
        "algorithm" => "Ed25519",
        "public_key" => Base64Url.encode(public_key),
        "status" => "active"
      }
    ],
    "attestation_hints" => [],
    "extensions" => %{"critical" => %{}, "optional" => %{}},
    "effective_from" => "2026-10-01T09:00:00Z"
  }

  {:ok, input} = CAP.descriptor_signing_input(%{"kid" => kid, "claims" => claims})
  compact = sign.(input, private_key)
  {:ok, decoded} = CAP.decode_party_descriptor(compact, limits)
  {compact, CAP.descriptor_digest(decoded)}
end

{issuer_descriptor, issuer_digest} =
  descriptor.("issuer-key", issuer_public, issuer_private)

{acceptor_descriptor, acceptor_digest} =
  descriptor.("acceptor-key", acceptor_public, acceptor_private)

descriptor_compacts = [issuer_descriptor, acceptor_descriptor]

# The genesis Charter Revision. Revisions are unsigned canonical JSON.
legal_text = "Supplier terms, version 1\n"

revision_claims = %{
  "protocol_revision" => 2,
  "revision_number" => 1,
  "parties" => [
    %{"party_descriptor_digest" => issuer_digest, "role" => "issuer"},
    %{"party_descriptor_digest" => acceptor_digest, "role" => "acceptor"}
  ],
  "legal_text" => %{
    "content_digest" => :legal_text |> Digest.hash(legal_text) |> Digest.to_tagged(),
    "media_type" => "text/plain",
    "uri_hint" => "https://example.com/supplier-terms.txt"
  },
  "precedence_declaration" => "legal_text_governs",
  "attribution_declaration" => %{"basis" => "bound_deployments"},
  "effective_from" => "2026-10-01T12:00:00Z",
  "termination_rules" => %{"reason_codes" => ["mutual", "breach"]},
  "abp_bindings" => [
    %{
      "party_role" => "issuer",
      "blueprint_id" => "example.demo/echo",
      "release_number" => 1,
      "content_digest" => "sha-256:b1Aw4cU5AbV9k8bdbZkRCsySDHGpTAwB-aQm57Wh7B8",
      "deployment_digest" => "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo"
    }
  ],
  "receipt_profile" => "com.example.charter/default",
  "extensions" => %{"critical" => %{}, "optional" => %{}}
}

{:ok, revision_bytes} = CAP.encode_charter_revision(revision_claims)
{:ok, revision} = CAP.decode_charter_revision(revision_bytes, limits)
revision_digest = CAP.revision_digest(revision)

# The genesis revision's digest is the charter's identity.
charter_id = revision_digest

# Each party accepts the revision. The producer checks the claims against the
# signer's own view of the charter before it returns anything to sign.
{:ok, view} = CAP.build_set([revision_bytes], [], [], descriptor_compacts)

accept = fn kid, descriptor_digest, role, private_key ->
  claims = %{
    "protocol_revision" => 2,
    "charter_id" => charter_id,
    "revision_number" => 1,
    "revision_digest" => revision_digest,
    "party_descriptor_digest" => descriptor_digest,
    "party_role" => role,
    "accepted_at" => "2026-10-01T13:00:00Z"
  }

  {:ok, input} = CAP.acceptance_signing_input(%{"kid" => kid, "claims" => claims}, view)
  sign.(input, private_key)
end

acceptance_compacts = [
  accept.("issuer-key", issuer_digest, "issuer", issuer_private),
  accept.("acceptor-key", acceptor_digest, "acceptor", acceptor_private)
]

{:ok, chain_facts} =
  CAP.verify_chain([revision_bytes], acceptance_compacts, descriptor_compacts, [], limits)
```

Every signed artifact here uses `"protocol_revision" => 2`. The default
producer signs with `Ed25519` at revision 2, and it refuses claims that name
another revision with `:signing_input_invalid`. To sign with `ML-DSA-65`,
pass `"algorithm" => "ML-DSA-65"` next to `"kid"` and `"claims"`, and set
`"protocol_revision" => 3`.

In production, produce artifacts with
[`charter_agreement_signer`](produce-and-verify.md). It holds no keys, calls
your key custody through a handle, and verifies each artifact with CAP before
it returns it. The setup above uses CAP's signing inputs directly so this page
depends on CAP alone.

## Verify a charter view you received

A counterparty sends you raw artifacts. Verify them as one view, then ask
which revision governs at the instant you care about.

```elixir
{:ok, chain_facts} =
  CAP.verify_chain([revision_bytes], acceptance_compacts, descriptor_compacts, [], limits)

at = ~U[2026-10-02 09:00:00Z]

governing =
  case CAP.governing_revision(chain_facts, at) do
    {:ok, :contested} -> :contested
    {:ok, :none} -> :none
    {:ok, digest} -> {:governed_by, digest}
  end

chain_facts.accepted_revision_digests
```

`verify_chain/5` decodes and checks every artifact from its bytes. It takes
the lists in the order revisions, acceptances, descriptors, terminations.
`build_set/4` takes revisions, acceptances, terminations, descriptors. Check
the order when you switch between them.

The facts print as `#CharterAgreementProtocol.ChainFacts<redacted>`, so read
the fields you need: `accepted_revision_digests`, `chain_topology`,
`fork_evidence`, `revision_facts`, `acceptance_facts` and `not_verified`.

The three governing results mean different things:

| Result | Meaning | What your application does |
|---|---|---|
| `{:ok, digest}` | exactly one revision governs at `at` | use that revision's terms |
| `{:ok, :contested}` | two accepted branches are both eligible | hold; the parties repair the fork (see below) |
| `{:ok, :none}` | nothing is in effect: before the first `effective_from`, or after a termination took effect | treat the charter as not in force at `at` |

## Narrow what a deployment accepts

A capability profile limits the signature algorithms and protocol revisions
one verification admits. Out-of-profile artifacts are rejected before any
signature check, the same way on every runtime.

```elixir
alias CharterAgreementProtocol.Capability.Profile

{:ok, ed25519_only} = Profile.new(algorithms: ["Ed25519"], revisions: {2, 3})

{:ok, _facts} =
  CAP.verify_chain(
    [revision_bytes],
    acceptance_compacts,
    descriptor_compacts,
    [],
    limits,
    ed25519_only
  )

{:ok, ml_dsa_only} = Profile.new(algorithms: ["ML-DSA-65"])

{:error, %CharterAgreementProtocol.Error{code: :algorithm_outside_profile}} =
  CAP.verify_chain(
    [revision_bytes],
    acceptance_compacts,
    descriptor_compacts,
    [],
    limits,
    ml_dsa_only
  )
```

A profile does not limit the key types a descriptor lists. To keep ML-DSA key
material out of a deployment, narrow the revision range to `{1, 2}`: ML-DSA
keys are legal only from protocol revision 3. See
[Integrate CAP into an application](integration.md) for when to use a profile.

## Compose and sign a receipt

The issuing party recorded one action under the charter and binds it to the
revision that governed it.

```elixir
receipt_claims = %{
  "protocol_revision" => 2,
  "charter_id" => charter_id,
  "revision_number" => 1,
  "revision_digest" => revision_digest,
  "issuing_party_role" => "issuer",
  "agent_party_role" => "issuer",
  "deployment_digest" => "sha-256:tWFr0caS0AWFJd2UcB9gZv3kNjIUP8xZ08WWM_h8xgo",
  "grant" => %{"scheme" => "host", "id" => "order-4711"},
  "invocation_id" => "invocation-2026-10-02-0001",
  "decision" => "accepted",
  "outcome" => "effect_committed",
  "occurred_at" => "2026-10-02T09:30:00Z",
  "recorded_at" => "2026-10-02T09:30:01Z",
  "extensions" => %{"critical" => %{}, "optional" => %{}}
}

{:ok, input} =
  CAP.receipt_signing_input(%{"kid" => "issuer-key", "claims" => receipt_claims})

receipt = sign.(input, issuer_private)

# Verify against the full chain view before you store or send the receipt.
{:ok, receipt_facts} = CAP.verify_receipt(receipt, chain_facts, limits)
receipt_facts.governing_match
```

`governing_match` is `:match` here: the revision the receipt names is the one
that governed at `occurred_at`. Inside an unresolved fork the same receipt
verifies with `:undetermined`.

`deployment_digest` must equal the revision's `abp_bindings` entry for the
`agent_party_role`. A `host`-scheme `grant` may omit `grant_digest`; a
`bap`-scheme one requires it. [Receipts](receipts.md) covers the members and
the allowed `decision` and `outcome` pairs.

You can also verify a receipt against the decoded revision alone, for
example before you hold the descriptors:

```elixir
{:ok, revision_only} = CAP.verify_receipt(receipt, revision, limits)

{revision_only.governing_match, :signature in revision_only.not_verified}
```

That form checks the receipt's structure and its match with the revision, but
not its signature: `signing_key_id` is `nil`, `governing_match` is
`:undetermined`, and `:signature` joins `not_verified`. Verify again with the
full chain view before you rely on the receipt.

## Rotate a party's signing key

Key rotation is a new Party Descriptor that succeeds the current one. The
successor is signed by a key that is active in its predecessor.

```elixir
{new_public, new_private} = :crypto.generate_key(:eddsa, :ed25519)

{:ok, current} = CAP.verify_descriptor(issuer_descriptor, nil, limits)

successor_claims = %{
  "protocol_revision" => 2,
  "party_id" => current.party_id,
  "prev_descriptor_digest" => current.descriptor_digest,
  "descriptor_number" => current.descriptor_number + 1,
  "verification_keys" => [
    %{
      "key_id" => "issuer-key-2",
      "algorithm" => "Ed25519",
      "public_key" => Base64Url.encode(new_public),
      "status" => "active"
    },
    %{
      "key_id" => "issuer-key",
      "algorithm" => "Ed25519",
      "public_key" => Base64Url.encode(issuer_public),
      "status" => "retired"
    }
  ],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-10-05T00:00:00Z"
}

# Sign with the key that is active in the predecessor.
{:ok, input} =
  CAP.descriptor_signing_input(%{"kid" => "issuer-key", "claims" => successor_claims})

successor = sign.(input, issuer_private)

{:ok, successor_facts} = CAP.verify_descriptor(successor, current, limits)
{:ok, issuer_history} = CAP.verify_descriptor_chain([issuer_descriptor, successor], limits)

Enum.map(issuer_history.descriptors, & &1.descriptor_position)
```

The history reads `[:superseded, :head]`. `party_id` stays the genesis
descriptor's digest for the party's whole history.

CAP verifies the predecessor facts you pass again from their retained bytes,
so a forged predecessor cannot skip the key check. A successor signed only by
its own new key fails with `:descriptor_key_invalid`. Counterparties learn of
the rotation when they receive the successor and verify the history again.

## Terminate the charter

A termination notice names the revision that governs at its own
`effective_at`. From that instant, `governing_revision/2` returns `:none`.

```elixir
termination_claims = %{
  "protocol_revision" => 2,
  "charter_id" => charter_id,
  "governing_revision_digest" => revision_digest,
  "party_descriptor_digest" => issuer_digest,
  "party_role" => "issuer",
  "reason_code" => "mutual",
  "effective_at" => "2026-12-31T00:00:00Z",
  "issued_at" => "2026-10-03T09:00:00Z"
}

{:ok, full_view} =
  CAP.build_set([revision_bytes], acceptance_compacts, [], descriptor_compacts)

{:ok, input} =
  CAP.termination_signing_input(
    %{"kid" => "issuer-key", "claims" => termination_claims},
    full_view
  )

termination = sign.(input, issuer_private)

{:ok, terminated} =
  CAP.verify_chain(
    [revision_bytes],
    acceptance_compacts,
    descriptor_compacts,
    [termination],
    limits
  )

before_end = CAP.governing_revision(terminated, ~U[2026-12-30 23:59:59Z])
at_end = CAP.governing_revision(terminated, ~U[2026-12-31 00:00:00Z])
```

`before_end` is `{:ok, revision_digest}` and `at_end` is `{:ok, :none}`. The
producer refuses with `:signing_refused` when the named revision does not
govern at `effective_at`, or when the revision's `termination_rules` do not
list the `reason_code`.

## Repair a contested fork

A fork appears when both parties accept two different revisions at the same
revision number. CAP's producer will not sign the second acceptance, so this
recipe signs it by hand to stand in for a party that did. Two sibling
revisions come first:

```elixir
alias CharterAgreementProtocol.Canonicalization

amend = fn text, overrides ->
  claims =
    revision_claims
    |> Map.merge(%{
      "charter_id" => charter_id,
      "legal_text" =>
        Map.put(
          revision_claims["legal_text"],
          "content_digest",
          :legal_text |> Digest.hash(text) |> Digest.to_tagged()
        )
    })
    |> Map.merge(overrides)

  {:ok, bytes} = CAP.encode_charter_revision(claims)
  {:ok, decoded} = CAP.decode_charter_revision(bytes, limits)
  {bytes, CAP.revision_digest(decoded)}
end

second = %{
  "revision_number" => 2,
  "prev_revision_digest" => revision_digest,
  "effective_from" => "2026-10-04T00:00:00Z"
}

{usd_bytes, usd_digest} = amend.("Supplier terms, settle in USD\n", second)
{eur_bytes, eur_digest} = amend.("Supplier terms, settle in EUR\n", second)

acceptance_claims = fn number, digest, previous, descriptor_digest, role ->
  %{
    "protocol_revision" => 2,
    "charter_id" => charter_id,
    "revision_number" => number,
    "revision_digest" => digest,
    "prev_revision_digest" => previous,
    "party_descriptor_digest" => descriptor_digest,
    "party_role" => role,
    "accepted_at" => "2026-10-04T01:00:00Z"
  }
end

# Accept through the producer, which checks the signer's current view first.
produce = fn kid, claims, private_key, revisions, acceptances ->
  {:ok, view} = CAP.build_set(revisions, acceptances, [], descriptor_compacts)
  {:ok, input} = CAP.acceptance_signing_input(%{"kid" => kid, "claims" => claims}, view)
  sign.(input, private_key)
end

revisions = [revision_bytes, usd_bytes, eur_bytes]

usd_issuer =
  produce.(
    "issuer-key",
    acceptance_claims.(2, usd_digest, revision_digest, issuer_digest, "issuer"),
    issuer_private,
    revisions,
    acceptance_compacts
  )

usd_acceptor =
  produce.(
    "acceptor-key",
    acceptance_claims.(2, usd_digest, revision_digest, acceptor_digest, "acceptor"),
    acceptor_private,
    revisions,
    acceptance_compacts ++ [usd_issuer]
  )

# The producer refuses to accept a sibling of a revision the party accepted.
{:ok, signer_view} =
  CAP.build_set(revisions, acceptance_compacts ++ [usd_issuer, usd_acceptor], [], descriptor_compacts)

{:error, %CharterAgreementProtocol.Error{code: :signing_refused}} =
  CAP.acceptance_signing_input(
    %{
      "kid" => "issuer-key",
      "claims" => acceptance_claims.(2, eur_digest, revision_digest, issuer_digest, "issuer")
    },
    signer_view
  )
```

Now sign the EUR acceptances by hand, verify the forked view, and see the
contest:

```elixir
sign_by_hand = fn kid, claims, private_key ->
  {:ok, header} =
    Canonicalization.encode_plain(%{"alg" => "Ed25519", "kid" => kid, "typ" => "cap+acceptance"})

  {:ok, payload} = Canonicalization.encode_plain(claims)
  message = Base64Url.encode(header) <> "." <> Base64Url.encode(payload)
  message <> "." <> Base64Url.encode(:crypto.sign(:eddsa, :none, message, [private_key, :ed25519]))
end

eur_acceptances = [
  sign_by_hand.(
    "issuer-key",
    acceptance_claims.(2, eur_digest, revision_digest, issuer_digest, "issuer"),
    issuer_private
  ),
  sign_by_hand.(
    "acceptor-key",
    acceptance_claims.(2, eur_digest, revision_digest, acceptor_digest, "acceptor"),
    acceptor_private
  )
]

acceptances = acceptance_compacts ++ [usd_issuer, usd_acceptor] ++ eur_acceptances

{:ok, forked} = CAP.verify_chain(revisions, acceptances, descriptor_compacts, [], limits)
{:ok, :contested} = CAP.governing_revision(forked, ~U[2026-10-05 00:00:00Z])

Enum.map(forked.fork_evidence, & &1.kind)
```

`fork_evidence` holds the sibling revisions and each party's two conflicting
acceptances. CAP picks no winner. The repair is a later revision, accepted by both
parties, that covers every competing branch: each is either its ancestor through
`prev_revision_digest` or listed in its `supersedes`. This one builds on USD and
lists both siblings in `supersedes`:

```elixir
{repair_bytes, repair_digest} =
  amend.("Supplier terms, settle in USD, repaired\n", %{
    "revision_number" => 3,
    "prev_revision_digest" => usd_digest,
    "supersedes" => Enum.sort([usd_digest, eur_digest]),
    "effective_from" => "2026-10-06T00:00:00Z"
  })

revisions = revisions ++ [repair_bytes]

repair_issuer =
  produce.(
    "issuer-key",
    acceptance_claims.(3, repair_digest, usd_digest, issuer_digest, "issuer"),
    issuer_private,
    revisions,
    acceptances
  )

repair_acceptor =
  produce.(
    "acceptor-key",
    acceptance_claims.(3, repair_digest, usd_digest, acceptor_digest, "acceptor"),
    acceptor_private,
    revisions,
    acceptances ++ [repair_issuer]
  )

{:ok, repaired} =
  CAP.verify_chain(
    revisions,
    acceptances ++ [repair_issuer, repair_acceptor],
    descriptor_compacts,
    [],
    limits
  )

{:ok, governing_after_repair} = CAP.governing_revision(repaired, ~U[2026-10-06 00:00:00Z])
```

`governing_after_repair` is the repair's digest. The producer signs the repair
acceptances because the repair supersedes both heads; it refuses any
acceptance whose ancestry leaves out an accepted head, so a party using it
cannot deepen a fork by accident. The
[fork-repair notebook](../notebooks/fork-repair.livemd) walks the same
sequence step by step.

## Handle errors at the call boundary

Every failure is a `%CharterAgreementProtocol.Error{}` with a `code` from a
closed set and a `subject` made only of protocol names and indexes. Neither
carries the rejected input, so both are safe to log.

```elixir
require Logger

[header, payload, signature] = String.split(hd(acceptance_compacts), ".")
{head, <<char, rest::binary>>} = String.split_at(signature, 10)
flipped = if char == ?A, do: ?B, else: ?A
tampered = Enum.join([header, payload, head <> <<flipped>> <> rest], ".")

result =
  CAP.verify_chain(
    [revision_bytes],
    [tampered | tl(acceptance_compacts)],
    descriptor_compacts,
    [],
    limits
  )

rejected_code =
  case result do
    {:ok, _facts} ->
      :verified

    {:error, %CharterAgreementProtocol.Error{code: code, subject: subject}} ->
      Logger.warning("charter view rejected: #{code} at #{Enum.join(subject, ".")}")
      code
  end
```

Changing one character of a signature gives `:signature_invalid` at
`compact_jws.signature`. Match the codes your application treats specially and
send the rest to your audit log. [Handle errors](error-codes.md) lists every
code with its cause and what to do.

## Record what you verified under

Store the artifact bytes, and next to them the identity of the verification
that accepted them. On replay, compare the identity before you trust a stored
result.

```elixir
alias CharterAgreementProtocol.{Algorithm, ReleaseIdentity}

manifest =
  :charter_agreement_protocol
  |> Application.app_dir("priv/release-metadata.json")
  |> File.read!()
  |> JSON.decode!()

limits_used =
  limits
  |> Map.from_struct()
  |> Map.new(fn {field, value} -> {Atom.to_string(field), value} end)

# One entry per artifact in the view. Revision facts carry `alg: nil`,
# because a Charter Revision is unsigned.
artifact = fn digest, facts ->
  %{"digest" => digest, "protocol_revision" => facts.protocol_revision, "alg" => facts.alg}
end

artifacts =
  Enum.map(chain_facts.revision_facts, &artifact.(&1.revision_digest, &1)) ++
    for(
      chain <- chain_facts.descriptor_chains,
      facts <- chain.descriptors,
      do: artifact.(facts.descriptor_digest, facts)
    ) ++
    Enum.map(chain_facts.acceptance_facts, &artifact.(&1.acceptance_digest, &1)) ++
    Enum.map(chain_facts.termination_facts, &artifact.(&1.termination_digest, &1))

verified_under = %{
  # Compare these on replay.
  "verification_semantics_version" => ReleaseIdentity.verification_semantics(),
  "limits" => limits_used,
  "signature_registry_digest" => Digest.to_tagged(Algorithm.registry_digest()),
  "artifacts" => artifacts,
  # Record these, but do not compare them on replay.
  "spec_digest" => manifest["spec_digest"],
  "corpus_digest" => manifest["corpus_digest"],
  "package_version" => manifest["package_version"]
}

verified_under["signature_registry_digest"] == manifest["signature_registry_digest"]
```

[Upgrade and persist verification identity](upgrading-verification-identity.md)
explains why each member is compared or only recorded.

## Run the conformance corpus in your CI

The package ships its conformance corpus. Running it on your own runtime
checks that CAP gives the expected result for every case there. The corpus
includes ML-DSA cases, so run it on a runtime where every
`CharterAgreementProtocol.capabilities/0` row says `verifiable: true` (OTP
linked against OpenSSL 3.5 or later).

```elixir
corpus = Application.app_dir(:charter_agreement_protocol, "priv/conformance")
exit_status = CharterAgreementProtocol.Conformance.Cli.run(["--corpus", corpus])
```

`run/1` prints the JSON report and returns `0` when every case agrees, `1`
when any case disagrees or the corpus fails to load, and `2` for bad
arguments. From a shell in your project, pass the status to the process exit
code with `System.halt/1`:

```console
$ mix run -e 'System.halt(CharterAgreementProtocol.Conformance.Cli.run(["--corpus", Application.app_dir(:charter_agreement_protocol, "priv/conformance")]))'
```

The CLI refuses a corpus whose index does not match the one this release
pins, so a corpus edited or regenerated anywhere else fails to load. See
[Conformance](conformance.md) for the corpus identities.
