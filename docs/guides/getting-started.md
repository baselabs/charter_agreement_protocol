# Your first verified charter

In this tutorial you install CAP, verify a real two-party
[charter](glossary.md), read what the verifier found, ask which revision
governs, and then break one byte to see how CAP reports it. It takes about
five minutes. You need no keys and no network beyond fetching the package.

The artifacts come from the conformance corpus that ships inside the package,
so you verify the same bytes every CAP implementation is tested against.

## Install

You need a Mix project. If you do not have one, create it first:

```console
$ mix new cap_tour
$ cd cap_tour
```

Add CAP to the dependencies in the project's `mix.exs`:

```elixir
def deps do
  [
    {:charter_agreement_protocol, "~> 0.5.0"}
  ]
end
```

CAP requires Elixir `~> 1.19` (tested on 1.19 and 1.20) on Erlang/OTP 28 or 29. ML-DSA verification
also needs OTP linked against OpenSSL 3.5 or later. CAP has no runtime
dependencies.

Run `mix deps.get`, then start a session with `iex -S mix`. Every block below
runs in that one session, in order.

## Check what this runtime can verify

```elixir
alias CharterAgreementProtocol, as: CAP

CAP.capabilities()
```

```text
%{
  algorithms: [
    %{name: "EdDSA", key_algorithm: "Ed25519", verifiable: true},
    %{name: "Ed25519", key_algorithm: "Ed25519", verifiable: true},
    %{name: "ML-DSA-44", key_algorithm: "ML-DSA-44", verifiable: true},
    %{name: "ML-DSA-65", key_algorithm: "ML-DSA-65", verifiable: true},
    %{name: "ML-DSA-87", key_algorithm: "ML-DSA-87", verifiable: true}
  ],
  linked_crypto: [{"OpenSSL", …}]
}
```

Each row says whether this runtime verified a pinned known-answer signature
for that algorithm. Your `linked_crypto` entry names your own OpenSSL build. A
row says `verifiable: false` when the runtime does not offer that algorithm or
cannot verify the pinned signature, for example because OTP is linked against
an OpenSSL older than 3.5 or the provider is disabled. Ed25519 artifacts still
verify, and an ML-DSA artifact fails with a typed error that says its signature
could not be checked, instead of a wrong answer.

Call this once at boot and log it. It tells you up front what the runtime will
refuse.

## Load a two-party artifact set

The corpus case `chain-dual-acceptance-valid` holds one charter
[revision](glossary.md), a [party descriptor](glossary.md) for each of the
two parties, and an [acceptance](glossary.md) signed by each party.

```elixir
corpus = Application.app_dir(:charter_agreement_protocol, "priv/conformance")

%{"cases" => cases} =
  corpus
  |> Path.join("cases/chain-verify.json")
  |> File.read!()
  |> JSON.decode!()

%{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))

Map.keys(set)
```

```text
["acceptances", "descriptors", "revisions", "terminations"]
```

The revision is unsigned canonical JSON: the terms both parties agree to. Each
descriptor is a signed compact JWS that pins one party's public key. Each
acceptance is one party's signed statement that it accepts the revision,
naming the revision's digest. There are no termination notices in this set.

## Verify the set

```elixir
{:ok, facts} =
  CAP.verify_chain(
    set["revisions"],
    set["acceptances"],
    set["descriptors"],
    set["terminations"],
    CAP.Limits.default()
  )
```

```text
{:ok, #CharterAgreementProtocol.ChainFacts<redacted>}
```

`verify_chain/5` checks every byte: canonical encoding, the descriptor
chains, every signature against the key its descriptor pins, and that each
acceptance names a revision in the set. It returns `{:ok, facts}` or a typed
error, never a partial answer.

The facts print as `<redacted>` so that charter contents do not end up in your
logs by accident. Read the fields you need directly.

## Read the facts

```elixir
Map.take(facts, [
  :charter_id,
  :chain_topology,
  :accepted_revision_digests,
  :superseded_revision_digests,
  :fork_evidence
])
```

```text
%{
  accepted_revision_digests: ["sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"],
  chain_topology: :linear,
  charter_id: "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o",
  fork_evidence: [],
  superseded_revision_digests: []
}
```

- `charter_id` names the charter. For the first revision it is that
  revision's own digest.
- `accepted_revision_digests` lists the revisions that both parties accepted.
- `chain_topology` is `:linear` when the accepted revisions that nothing
  supersedes form one line of history through their `prev_revision_digest`
  links, and `:forked` when they branch. A repaired fork reads `:linear` again,
  while `accepted_revision_digests` still lists the old branches.
- `superseded_revision_digests` lists accepted revisions that a later accepted
  revision names in its `supersedes` list.
- `fork_evidence` holds the signed proof of any fork. CAP reports a fork and
  never picks a winner.

Each acceptance has its own facts:

```elixir
for acceptance <- facts.acceptance_facts do
  {acceptance.party_role, acceptance.signing_key_id, acceptance.alg,
   acceptance.protocol_revision}
end
```

```text
[
  {"acceptor", "acceptor-key", "EdDSA", 1},
  {"issuer", "genesis-key", "EdDSA", 1}
]
```

These two acceptances were signed under `EdDSA` at protocol revision 1, the
first version of the protocol. This release still verifies them under the
default full profile; a profile that narrows the revisions, such as
`revisions: {2, 3}`, refuses them. New artifacts are signed as `Ed25519` at
revision 2, which the next tutorial does.

Every facts record also lists what CAP did not check:

```elixir
facts.not_verified
```

```text
[:tenancy, :live_policy, :authority, :effect_ownership, :execution, :billing,
 :evaluation_truth, :legal_validity, :term_satisfaction, :view_completeness,
 :counterparty_view, :wall_clock]
```

CAP proves who signed what. It does not decide whether your application should
act on it. Each atom names a question your application answers, if it cares
about it. [Security model](security-model.md) walks through the list.

## Ask which revision governs

```elixir
CAP.governing_revision(facts, ~U[2026-09-01 00:00:00Z])
```

```text
{:ok, "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"}
```

The [governing revision](glossary.md) is the one accepted revision in force at
that instant. Pass the time you care about; CAP never reads the clock. Before
the revision's `effective_from` of `2026-08-25T12:00:00Z`, nothing governs:

```elixir
CAP.governing_revision(facts, ~U[2026-08-25 11:59:59Z])
```

```text
{:ok, :none}
```

A revision only one party accepted does not govern either. Verify the set with
the acceptor's acceptance alone:

```elixir
{:ok, one_sided} =
  CAP.verify_chain(
    set["revisions"],
    tl(set["acceptances"]),
    set["descriptors"],
    set["terminations"],
    CAP.Limits.default()
  )

CAP.governing_revision(one_sided, ~U[2026-09-01 00:00:00Z])
```

```text
{:ok, :none}
```

The third answer is `:contested`, when two accepted revisions compete for the
same instant. [Verification semantics](verification.md) covers it. Your
application decides what to do with `:none` and `:contested`;
[Integrate CAP into an application](integration.md) has the patterns.

## Change one byte

Change one letter in the revision's termination reasons, from `breach` to
`breacH`, and verify again:

```elixir
[revision] = set["revisions"]
tampered = String.replace(revision, "breach", "breacH")

CAP.verify_chain(
  [tampered],
  set["acceptances"],
  set["descriptors"],
  set["terminations"],
  CAP.Limits.default()
)
```

```text
{:error,
 %CharterAgreementProtocol.Error{
   code: :chain_invalid,
   subject: ["chain"],
   detail: nil
 }}
```

The changed bytes are still a well-formed revision, but their digest is new,
and both acceptances name the old digest. Nothing in the set accepts the new
terms, so the set fails as a whole. Change a byte of either acceptance's
signature instead and the code is `:signature_invalid`.

Errors carry a `code` and a `subject` path and never echo the input, so they
are safe to log. [Handle errors](error-codes.md) lists every code with its
cause and what to do.

## Optional: run the conformance corpus

The package can check itself against its whole shipped corpus. This step needs
a runtime on which every `capabilities/0` row says `verifiable: true`, because
the corpus includes ML-DSA cases. On a runtime without ML-DSA, skip it; the
steps above do not need it.

```elixir
CharterAgreementProtocol.Conformance.Cli.run(["--corpus", corpus])
```

It prints a canonical JSON report (`"agreement":true` when every case agrees)
and returns `0`. From a shell in your project:

```console
$ mix run -e 'System.halt(CharterAgreementProtocol.Conformance.Cli.run(["--corpus", Application.app_dir(:charter_agreement_protocol, "priv/conformance")]))'
```

The exit status is `0` when every case agrees, `1` when the corpus fails to
load or a case disagrees, and `2` on a usage error. [Conformance](conformance.md)
describes the corpus.

## Next

- [Produce and verify with the signer](produce-and-verify.md): mint your own
  descriptors, revision and acceptances, then verify them as the other party
  would.
- [Overview](overview.md): what each artifact is and how they fit together.
- [Integrate CAP into an application](integration.md): limits, profiles,
  storage and the time source.
