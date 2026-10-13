# Limits and profiles

Two inputs decide how much a verification call will accept. `Limits` bounds sizes.
`Capability.Profile` narrows which signature algorithms and protocol revisions you
accept. Both are plain data that you pass on each call. CAP reads no application
config and no environment for either.

## Limits

Every artifact decode and verify function in `CharterAgreementProtocol` takes a
`%CharterAgreementProtocol.Limits{}`. Lower-level helpers such as
`Canonicalization.verify/1`, `Base64Url.decode/1` and `Signature.verify/4` do not.
Input bytes and the two set limits are checked before CAP parses anything; nesting
depth, member and item counts and string sizes are checked while the JSON is parsed.

| Field | Default | Maximum | What it bounds |
|---|---:|---:|---|
| `max_bytes` | 1,048,576 | 16,777,216 | The bytes of one input: one JSON document, one revision, or one compact JWS |
| `max_depth` | 64 | 128 | How deeply arrays and objects nest inside one JSON value |
| `max_object_members` | 1,024 | 65,536 | Members in any one object |
| `max_array_items` | 4,096 | 65,536 | Items in any one array |
| `max_string_bytes` | 65,536 | 1,048,576 | UTF-8 bytes in any one string or member name, counted after unescaping |
| `max_artifact_set_items` | 1,024 | 4,096 | Items in each list you pass to `verify_chain`, counted per list, and descriptors passed to `verify_descriptor_chain` |
| `max_artifact_set_bytes` | 67,108,864 | 1,073,741,824 | The total bytes of all four lists you pass to `verify_chain`, added together |

The two set limits work differently. `max_artifact_set_items` applies to the
revisions, acceptances, descriptors and terminations lists one at a time, so the
default lets each list hold up to 1,024 items. `max_artifact_set_bytes` is one budget
for everything in the call. Both are checked before CAP decodes anything or checks any
signature.

A value exactly at a limit is accepted. One more fails with `:limit_exceeded`, and the
error's subject names the limit, for example `["chain", "bytes"]` or
`["json", "depth"]`. Inside a signed artifact the JSON limits surface differently: a
depth, member, item or string limit exceeded in the protected header fails with
`:protected_header_invalid`, and one exceeded in the payload fails with
`:non_canonical_bytes`. `max_bytes` on a compact still fails with `:limit_exceeded`.

### Choosing limits

Start from the defaults and narrow what you know your charters never need:

```elixir
alias CharterAgreementProtocol.Limits

{:ok, limits} = Limits.new(max_artifact_set_items: 64, max_artifact_set_bytes: 8_388_608)
```

`Limits.new/1` takes any subset of the fields; the rest keep their defaults. It returns
`{:error, %Error{code: :invalid_limits}}` for a value above its maximum, a negative
value, a field name it does not know, or a field given twice. Zero is a valid value.
`Limits.default/0` and `Limits.maximums/0` return the two columns above, and
`Limits.fields/0` lists the field names.

Pass the struct `Limits.new/1` returned. A struct you build by hand with an
out-of-range value fails at the call with `:invalid_limits`.

The functions that build signing inputs and `assemble_compact/2` always check against
`Limits.default()`, so an artifact you produce must fit the default limits.

## Capability profiles

A profile narrows two things:

- `algorithms`: the protected-header `alg` names you accept;
- `revisions`: the `protocol_revision` range you accept, as `{min, max}`.

Both apply to every signed artifact a call verifies, and the revision range also
applies to each Charter Revision, which is unsigned. That includes the context a
standalone call verifies again: `verify_acceptance/5` and `verify_termination/5`
check the supplied revision first, then each descriptor in the supplied chain, then
the artifact; `verify_receipt/4` checks the chain view (as `verify_chain/6` does) or
the bare revision, then the receipt. A receipt's envelope (its `alg` and
`protocol_revision`) is admitted against the profile before any key is looked up,
so it fails with the profile code even against a bare revision, where its signature
stays unchecked, or when its `kid` names no key. A successor descriptor given to
`verify_descriptor/4` has its predecessor history checked against the profile too.

An artifact outside the profile fails with `:algorithm_outside_profile` or
`:revision_outside_profile` before its own signature is checked, so it never reaches
a signature verdict. Artifacts the call checked earlier, such as the context, may
already have had their signatures verified.

`Profile.full/0` is every registry name and revisions 1 to 3. A call without a profile
behaves exactly like a call with `Profile.full/0`. A profile can only narrow; there is
no way to admit something the registry does not.

```elixir
alias CharterAgreementProtocol.Capability.Profile

# Accept Ed25519 signatures only.
{:ok, ed25519_only} = Profile.new(algorithms: ["EdDSA", "Ed25519"])

# Accept protocol revisions 1 and 2 only.
{:ok, revisions_1_and_2} = Profile.new(revisions: {1, 2})
```

`Profile.new/1` takes `:algorithms` (a non-empty list of registry names without
repeats) and `:revisions` (`{min, max}` within 1 to 3, with `min <= max`). Leave
either out, or pass `nil`, to keep the full value. Anything else returns
`{:error, %Error{code: :invalid_profile}}`, and a malformed profile struct passed to a
verify call fails the same way before verification starts.

These functions take a profile as their last argument:

- `verify_descriptor/4`
- `verify_descriptor_chain/3`
- `verify_acceptance/5`
- `verify_termination/5`
- `verify_receipt/4`
- `verify_chain/6`

### Profiles and descriptor keys

A profile checks the `alg` of each signature, not the keys a descriptor declares. A
descriptor at `protocol_revision` 3 may declare an ML-DSA key and still be signed with
Ed25519 by its predecessor's key; `ed25519_only` above accepts it. To refuse every
history that declares ML-DSA keys, narrow the revisions instead: ML-DSA keys are only
legal from `protocol_revision` 3, so `revisions_1_and_2` refuses that descriptor with
`:revision_outside_profile`.

## What this runtime can verify

`CharterAgreementProtocol.capabilities/0` reports which registry algorithms the
running Erlang runtime can verify. It verifies a known-answer signature for each key
algorithm, so the answer comes from a real verification, not from what the runtime
says about itself.

```elixir
CharterAgreementProtocol.capabilities()
#=> %{
#=>   algorithms: [
#=>     %{name: "EdDSA", key_algorithm: "Ed25519", verifiable: true},
#=>     %{name: "Ed25519", key_algorithm: "Ed25519", verifiable: true},
#=>     %{name: "ML-DSA-44", key_algorithm: "ML-DSA-44", verifiable: true},
#=>     %{name: "ML-DSA-65", key_algorithm: "ML-DSA-65", verifiable: true},
#=>     %{name: "ML-DSA-87", key_algorithm: "ML-DSA-87", verifiable: true}
#=>   ],
#=>   linked_crypto: [{"OpenSSL", ...}]
#=> }
```

`linked_crypto` names the crypto library OTP is linked against. It is there for your
logs and plays no part in the answer.

Call it once at boot and build your profile from it, so the application states up
front what it can verify:

```elixir
report = CharterAgreementProtocol.capabilities()
names = for %{name: name, verifiable: true} <- report.algorithms, do: name
{:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(algorithms: names)
```

If no algorithm is verifiable, `names` is empty and `Profile.new/1` returns
`:invalid_profile`; treat that as a failed boot.

The report is a snapshot. Each verify call still checks for itself: on a runtime that
cannot verify an artifact's algorithm, the call fails with
`:algorithm_unsupported_on_substrate`. That error describes the runtime, not the
artifact, and it is not part of the conformance results. Two correct verifiers on
different runtimes can differ on it for the same bytes.
