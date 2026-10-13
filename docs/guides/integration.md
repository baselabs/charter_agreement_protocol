# Integrate CAP into an application

CAP is a pure library. You hand it artifact bytes, an instant, limits and an
optional profile. It returns verified facts or a typed error. It reads no
clock, opens no network connection and holds no keys; the conformance CLI,
which reads a corpus directory, is the only part that touches the
filesystem.

CAP never authorizes anything. A verified charter tells you what two parties
signed and which revision governs at a given instant. Whether your
application does anything because of it is for your application to decide.

This page covers the calls an application makes, in the order it makes them.
The code blocks run in sequence, and the test suite runs them, so they match
the current release. [Recipes](recipes.md) has longer worked examples.

## At boot: check what the runtime can verify

```elixir
alias CharterAgreementProtocol, as: CAP
alias CharterAgreementProtocol.Capability.Profile

report = CAP.capabilities()

verifiable = for %{name: name, verifiable: true} <- report.algorithms, do: name
unverifiable = for %{name: name, verifiable: false} <- report.algorithms, do: name
```

`capabilities/0` reports, for each signature algorithm in the registry,
whether this runtime can verify it. Each answer comes from verifying a pinned
known-answer signature, not from what the runtime says about itself.
`report.linked_crypto` names the crypto library for your logs; it does not
change the answers.

ML-DSA (`ML-DSA-44`, `ML-DSA-65`, `ML-DSA-87`) needs Erlang/OTP 28 or 29
linked against OpenSSL 3.5 or later. On a runtime linked against OpenSSL 3.0,
only the Ed25519 rows verify. When `unverifiable` is not empty, pick one of
these:

- **Your charters use only Ed25519.** Do nothing. ML-DSA artifacts you
  receive fail with `:algorithm_unsupported_on_substrate`.
- **You want the same answer on every machine.** Build a profile from the
  verifiable names (next section) and pass it on every verify call. An
  ML-DSA artifact then fails with `:algorithm_outside_profile` before its
  signature is checked, whatever the runtime.
- **Your charters need ML-DSA.** Fail the boot and run on a runtime linked
  against OpenSSL 3.5 or later.

The report is a snapshot for setting policy at boot. Every verify call still
checks the runtime itself. `:algorithm_unsupported_on_substrate` means "this
runtime cannot check this signature", not "invalid" and not "verified". The
checks that ran before it passed, but the signature's validity is unknown: a
forged signature of the right length gets the same error. Retry on a capable
runtime, or treat the artifact as unverified.

## Choose a profile

```elixir
{:ok, profile} = Profile.new(algorithms: verifiable)
```

A profile narrows two things per artifact: the signature algorithm names
(`alg`) and the `protocol_revision` range. It applies to every artifact a call
verifies, including the revision, descriptor chain or chain view you pass as
context to `verify_acceptance/5`, `verify_termination/5` and `verify_receipt/4`.
Without one, CAP admits the full registry and every revision, which is the same
as `Profile.full/0`.

Pass a profile when:

- the runtime cannot verify some algorithms and you want a fixed rejection
  instead of a runtime-dependent one;
- your deployment accepts fewer algorithms or revisions than the protocol
  does. For example, `revisions: {2, 3}` refuses revision-1 artifacts, which
  use the legacy `EdDSA` name;
- you must keep ML-DSA key material out. A profile does not limit the key
  types a descriptor lists, so narrow the revision range to `{1, 2}`: ML-DSA
  keys are legal only from revision 3.

Every verify function has a form that takes a profile as its last argument:
`verify_chain/6`, `verify_receipt/4`, `verify_descriptor/4`,
`verify_descriptor_chain/3`, `verify_acceptance/5` and
`verify_termination/5`. A malformed profile fails with `:invalid_profile`
before verification starts. Out-of-profile artifacts fail with
`:algorithm_outside_profile` or `:revision_outside_profile`.

## Choose and pin limits

```elixir
alias CharterAgreementProtocol.Limits

{:ok, limits} = Limits.new(max_bytes: 262_144, max_artifact_set_items: 256)

{:error, %CharterAgreementProtocol.Error{code: :invalid_limits}} =
  Limits.new(max_bytes: 32_000_000)
```

Limits bound the work CAP does on input you did not create. Every verify call
takes them. `Limits.new/1` starts from the defaults, applies your values, and
refuses unknown fields and values above the maximum.

| Field | Default | Maximum | Bounds |
|---|---|---|---|
| `max_bytes` | 1,048,576 | 16,777,216 | bytes in one artifact |
| `max_depth` | 64 | 128 | JSON nesting depth |
| `max_object_members` | 1,024 | 65,536 | members in one JSON object |
| `max_array_items` | 4,096 | 65,536 | items in one JSON array |
| `max_string_bytes` | 65,536 | 1,048,576 | bytes in one JSON string |
| `max_artifact_set_items` | 1,024 | 4,096 | artifacts in each list of a chain view |
| `max_artifact_set_bytes` | 67,108,864 | 1,073,741,824 | bytes across all lists of a chain view |

Start from the defaults and lower the fields your traffic never reaches;
lower limits reject oversized input sooner. Raise a field only when real
artifacts need it. Input over a limit fails with `:limit_exceeded`.

Build the limits once, explicitly, and record the values next to what you
store. A change to any default value counts as a change in verification
semantics, so pinning your own values keeps your results independent of the
defaults. [Upgrade and persist verification identity](upgrading-verification-identity.md)
covers what to record.

## Verify what you receive

The package ships a conformance corpus. Its `chain-dual-acceptance-valid`
case is a real two-party charter, so it serves here as the artifacts a
counterparty sent you:

```elixir
cases_file =
  Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")

%{"cases" => cases} = cases_file |> File.read!() |> JSON.decode!()
%{"input" => received} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))

{:ok, chain_facts} =
  CAP.verify_chain(
    received["revisions"],
    received["acceptances"],
    received["descriptors"],
    received["terminations"],
    limits,
    profile
  )
```

`verify_chain/6` takes the lists in the order revisions, acceptances,
descriptors, terminations. Each list holds raw bytes: revision JSON, and
compact JWS strings for the rest. CAP checks every artifact from those bytes
and trusts nothing the artifacts say about each other until it has checked
it.

## Ask which revision governs, and at what time

```elixir
which_governs = fn facts, at ->
  case CAP.governing_revision(facts, at) do
    {:ok, :contested} -> :contested
    {:ok, :none} -> :not_in_force
    {:ok, digest} -> {:governed_by, digest}
    {:error, %CharterAgreementProtocol.Error{code: code}} -> {:rejected, code}
  end
end

now = which_governs.(chain_facts, DateTime.utc_now())
before_start = which_governs.(chain_facts, ~U[2026-08-01 00:00:00Z])
```

CAP reads no clock, so every governing question carries its own instant:

- for "what governs now", pass the current UTC time from your clock;
- for "what governed when this happened", pass the event's own time. Receipts
  do this for you: `verify_receipt` computes governance at the receipt's
  `occurred_at`.

The instant is a `DateTime` in UTC or a `%CharterAgreementProtocol.Timestamp{}`
from `Timestamp.parse/1`. A `DateTime` in another time zone fails with
`:governing_invalid`; a string fails with `:invalid_type`. Convert first.

Each result needs its own handling:

- `{:ok, digest}`: exactly one revision governs. Use that revision's terms.
- `{:ok, :contested}`: two accepted revisions compete and CAP picks neither.
  `chain_facts.fork_evidence` holds the signed evidence. Do not choose a
  branch yourself; hold until the parties sign a repair revision that
  supersedes both. [Recipes](recipes.md) shows the repair.
- `{:ok, :none}`: nothing is in force at that instant. No accepted revision
  is in effect then (for example, the instant is before the first
  `effective_from`), or a verified termination took effect.

## Log errors safely

```elixir
require Logger

{:error, error} =
  CAP.verify_chain(
    [hd(received["revisions"]) <> " "],
    received["acceptances"],
    received["descriptors"],
    [],
    limits
  )

Logger.warning("charter view rejected: #{error.code} at #{Enum.join(error.subject, ".")}")
```

Every error is a `%CharterAgreementProtocol.Error{}`. `code` comes from a
closed set, `subject` holds only protocol names and indexes, and `detail` is
`nil` in this release. None of them contains the input that failed, so you can
log all three. Here the trailing space makes the revision bytes non-canonical,
and the log line reads `charter view rejected: non_canonical_bytes at
charter_revision`.

Facts records print as `#CharterAgreementProtocol.ChainFacts<redacted>` (and
the same for the other facts records), so an accidental `inspect` leaks
nothing. Log a field on purpose when you need it. Treat the artifact bytes
like any other business document under your own data policy.

[Handle errors](error-codes.md) lists every code, its cause, and what to do.

## Store what you verified

Store the artifact bytes exactly as received. They are the evidence: anyone
can verify them again later, with this release or another implementation.
Facts are a projection you can always recompute from the bytes.

Next to the bytes, store the identity of the verification that accepted them:
the verification semantics version, the limits you used, the signature
registry digest, and each artifact's `protocol_revision` and `alg`.
[Upgrade and persist verification identity](upgrading-verification-identity.md)
explains which of these to compare on replay, and
[Recipes](recipes.md) builds the record in code.

## Verify after you produce

`assemble_compact/2` checks the signature's length and the artifact's
structure. It does not check that the signature belongs to the right key.
Verify every artifact you produce before you store it or send it:

```elixir
{public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
{_other_public, other_private} = :crypto.generate_key(:eddsa, :ed25519)

claims = %{
  "protocol_revision" => 2,
  "descriptor_number" => 1,
  "verification_keys" => [
    %{
      "key_id" => "party-key",
      "algorithm" => "Ed25519",
      "public_key" => CharterAgreementProtocol.Base64Url.encode(public_key),
      "status" => "active"
    }
  ],
  "attestation_hints" => [],
  "extensions" => %{"critical" => %{}, "optional" => %{}},
  "effective_from" => "2026-10-01T09:00:00Z"
}

{:ok, input} = CAP.descriptor_signing_input(%{"kid" => "party-key", "claims" => claims})

# A signature from the wrong key still assembles.
wrong_signature = :crypto.sign(:eddsa, :none, input.message, [other_private, :ed25519])
{:ok, wrong} = CAP.assemble_compact(input, wrong_signature)
{:error, %CharterAgreementProtocol.Error{code: :signature_invalid}} =
  CAP.verify_descriptor(wrong, nil, limits)

{:ok, plan} = CAP.prepare_signing(
  :party_descriptor,
  %{"kid" => "party-key", "claims" => claims, "public_key" => public_key},
  nil,
  limits,
  profile
)
signature = :crypto.sign(:eddsa, :none, plan.signing_input.message, [private_key, :ed25519])
{:ok, descriptor} = CAP.finish_signing(plan, signature)
{:ok, descriptor_facts} = CAP.verify_descriptor(descriptor, nil, limits)
descriptor_facts.signing_key_id
```

Use the full context when you verify: the verified descriptor history for an
acceptance or termination, and the full chain facts for a receipt.

[`charter_agreement_signer`](produce-and-verify.md) does this for you. It
signs through a handle to your key custody, checks the signature against the
key before it assembles the artifact, and runs the matching CAP verify
function before it returns. If you call CAP's signing inputs directly, the
verify step is yours.

### Check before external signing

Pass the holder's snapshot public key as raw bytes. CAP derives and keeps
its verification context in the returned plan. Acceptance and termination
use an `ArtifactSet`; a descriptor uses nil or predecessor facts; a receipt
uses `ChainFacts` or a `CharterRevision`. A bare revision returns
`key: :unnamed` because it names no descriptor key.

Keep the plan as returned. `finish_signing/2` assembles under its limits
and runs public verification with its context and profile. Limits apply
to every byte CAP reads in the whole retained set. `Profile.full()` applies
to the set check for producer refusals. The caller profile applies to the
revision, signing party's descriptor history and artifact for acceptance
and termination, the whole retained set for a receipt, and the predecessor
history and artifact for a descriptor. The old signing-input functions
and `assemble_compact/2` continue to use default limits; use this flow for
the key check and explicit limits.
## What CAP leaves to your application

CAP checks that artifacts are well formed, correctly signed, consistent with
each other, and which revision governs at an instant. These stay with you:

- **Trust in the parties.** CAP checks that a descriptor history is
  internally sound from its genesis. It does not know who controls a genesis
  key. Decide which `party_id` values you accept as a given counterparty, and
  pin them.
- **Key revocation.** CAP has no revocation list. A party rotates keys by
  publishing a successor descriptor. Artifacts that name an older descriptor
  still verify, and their facts report `descriptor_position: :superseded`.
  Decide whether you accept them, and fetch descriptor updates through your
  own channel.
- **A complete view.** CAP verifies the artifacts you pass. It cannot know
  about artifacts you were not sent, such as a later revision or a
  termination. Collecting a complete view is your job.
- **The network and the clock.** CAP fetches nothing and reads no time. You
  supply the bytes and the instant.
- **Policy.** Whether a governing revision is enough to proceed, what its
  legal text means, and whether its terms are met are your application's
  questions.

Every facts record lists these limits in `not_verified`, a fixed list of the
things CAP did not check, from tenancy to wall-clock truth. A verified result
never removes an item from that list. The [security model](security-model.md)
has the full host checklist.
