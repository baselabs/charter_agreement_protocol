defmodule CharterAgreementProtocol do
  @moduledoc """
  Verify charter agreements between two parties. CAP never authorizes.

  A charter is a set of artifacts: Party Descriptors (each party's signed key
  record), Charter Revisions (the unsigned terms), Acceptances (one party's
  signed assent to one revision) and termination notices. This module is the
  entry point. It checks those artifacts byte for byte and returns facts about
  them. Whether those facts allow anything is your application's decision.

  Every function here is pure. It reads no clock, file, environment or
  application config, and it never holds or uses a private key.

  ## Verify a charter

  Pass the whole artifact set to `verify_chain/5`. It verifies every artifact
  again, checks how they link, and returns a `CharterAgreementProtocol.ChainFacts`
  record or a typed `CharterAgreementProtocol.Error`. This example verifies the
  two-party set that ships in the conformance corpus:

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> {:ok, facts} =
      ...>   CharterAgreementProtocol.verify_chain(
      ...>     set["revisions"],
      ...>     set["acceptances"],
      ...>     set["descriptors"],
      ...>     set["terminations"],
      ...>     CharterAgreementProtocol.Limits.default()
      ...>   )
      iex> facts.chain_topology
      :linear
      iex> facts.accepted_revision_digests
      ["sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"]
      iex> CharterAgreementProtocol.governing_revision(facts, ~U[2026-09-01 00:00:00Z])
      {:ok, "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"}

  ## Read the facts

  Facts records are plain structs. Read their fields directly. `inspect/2`
  prints them as `#CharterAgreementProtocol.ChainFacts<redacted>` so that
  charter contents stay out of logs; pass `structs: false` to `inspect/2` when
  you need to see every field while debugging.

  Every facts record has a `not_verified` list. It names what CAP did not
  check and your application must establish itself, such as legal validity and
  whether the view you hold is complete. See `CharterAgreementProtocol.Facts`
  for the list and the [security model](security-model.md) for what it means.

  ## Ask which revision governs

  `governing_revision/2` takes verified chain facts and an instant you supply.
  It returns the digest of the one revision that governs at that instant,
  `:contested` when signed revisions compete, or `:none` when nothing governs.
  Plan for all three results.

  Digests are strings of the form `"sha-256:<base64url>"`: the SHA-256 hash of
  the artifact's content under a per-artifact domain separator, encoded as
  unpadded base64url. The content is a revision's canonical bytes, or a
  signed artifact's payload bytes without the signature.

  ## Produce artifacts

  CAP builds the exact bytes to sign and checks the result, but it never
  signs. To produce artifacts, use the `charter_agreement_signer` package,
  which calls these functions and does the signing. To sign with your own key
  instead:

  1. Build a signing input: `descriptor_signing_input/1`,
     `acceptance_signing_input/2`, `termination_signing_input/2` or
     `receipt_signing_input/1`.
  2. Sign the input's `message` bytes with your key, outside CAP.
  3. Pass the raw signature to `assemble_compact/2` to get the compact JWS.
  4. Verify the result before you use it.

  The claims' `protocol_revision` must match the algorithm you sign with: 2
  for `"Ed25519"` (the default) and 3 for `"ML-DSA-65"`.

  ## Limits, profiles and errors

  Every artifact decode and verify call takes a `CharterAgreementProtocol.Limits`
  value. Input bytes and artifact-set sizes are checked before parsing;
  nesting depth, member and item counts and string sizes are checked while
  the JSON is parsed. Use
  `CharterAgreementProtocol.Limits.default/0` unless you need tighter
  bounds. The verify functions also accept an optional
  `CharterAgreementProtocol.Capability.Profile` that narrows which algorithms
  and protocol revisions you accept.

  Failures are `{:error, %CharterAgreementProtocol.Error{}}`. An error names a
  code and a protocol-owned subject and never echoes your input. See
  [Handle errors](error-codes.md) for each code.
  """

  alias CharterAgreementProtocol.{
    Acceptance,
    AcceptanceFacts,
    ArtifactSet,
    Chain,
    ChainFacts,
    CharterRevision,
    DescriptorChain,
    DescriptorFacts,
    Limits,
    PartyDescriptor,
    Receipt,
    ReceiptFacts,
    SigningInput,
    TerminationFacts,
    TerminationNotice
  }

  alias CharterAgreementProtocol.Capability.Profile

  @doc """
  Decode one Party Descriptor and check its structure.

  `compact` is the descriptor's compact JWS string (`typ` `"cap+party"`).
  The bytes must be canonical and within `limits`. This checks the
  descriptor's shape, keys and extensions, not its signature: use
  `verify_descriptor/3` for that.

  Returns `{:ok, %CharterAgreementProtocol.PartyDescriptor{}}` or a typed
  error.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, descriptor} = CharterAgreementProtocol.decode_party_descriptor(hd(set["descriptors"]), limits)
      iex> descriptor.descriptor_number
      1
      iex> CharterAgreementProtocol.decode_party_descriptor("not a compact", limits)
      {:error, %CharterAgreementProtocol.Error{code: :compact_invalid, subject: ["compact_jws"], detail: nil}}
  """
  @spec decode_party_descriptor(term(), Limits.t()) ::
          {:ok, PartyDescriptor.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate decode_party_descriptor(compact, limits), to: PartyDescriptor, as: :decode

  @doc """
  Return a decoded Party Descriptor's content digest.

  The digest is a `"sha-256:<base64url>"` string. Revisions, Acceptances and
  termination notices name a descriptor by this value in their
  `party_descriptor_digest` member. A genesis descriptor's digest is also the
  party's id for its whole descriptor chain.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, descriptor} = CharterAgreementProtocol.decode_party_descriptor(hd(set["descriptors"]), limits)
      iex> CharterAgreementProtocol.descriptor_digest(descriptor)
      "sha-256:1ynn3VZQs_pAZVjrnDn-DzEUMc8gJV0FMFV3SFONZIU"
  """
  @spec descriptor_digest(PartyDescriptor.t()) :: binary()
  defdelegate descriptor_digest(descriptor), to: PartyDescriptor, as: :digest

  @doc """
  Verify one Party Descriptor's signature, at genesis or after a predecessor.

  Pass `nil` as `predecessor` for a genesis descriptor (`descriptor_number`
  1). It must be signed by one of its own active keys. For a later
  descriptor, pass the `CharterAgreementProtocol.DescriptorFacts` you got
  from verifying the one before it. The new descriptor must carry the next
  number, name the predecessor's digest, keep the same `party_id`, and be
  signed by a key that is active in the predecessor. CAP verifies the
  predecessor's whole lineage again, so an edited facts struct is not
  trusted.

  Returns `{:ok, %CharterAgreementProtocol.DescriptorFacts{}}` with
  `descriptor_position: :head`. Positions across several descriptors come
  from `verify_descriptor_chain/2`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, facts} = CharterAgreementProtocol.verify_descriptor(hd(set["descriptors"]), nil, limits)
      iex> {facts.descriptor_number, facts.descriptor_position, facts.signing_key_id}
      {1, :head, "genesis-key"}
      iex> facts.party_id
      "sha-256:1ynn3VZQs_pAZVjrnDn-DzEUMc8gJV0FMFV3SFONZIU"
  """
  @spec verify_descriptor(term(), nil | DescriptorFacts.t(), Limits.t()) ::
          {:ok, DescriptorFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  @spec verify_descriptor(term(), nil | DescriptorFacts.t(), Limits.t(), Profile.t()) ::
          {:ok, DescriptorFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_descriptor(compact, predecessor, limits), to: PartyDescriptor, as: :verify

  @doc """
  Verify one Party Descriptor under a capability profile.

  Same as `verify_descriptor/3`, but a descriptor whose `alg` or
  `protocol_revision` is outside `profile` fails with
  `:algorithm_outside_profile` or `:revision_outside_profile` before its own
  signature is checked. The profile also applies to every descriptor in the
  supplied predecessor history, which is verified first.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(algorithms: ["Ed25519"])
      iex> CharterAgreementProtocol.verify_descriptor(hd(set["descriptors"]), nil, limits, profile)
      {:error, %CharterAgreementProtocol.Error{code: :algorithm_outside_profile, subject: ["compact_jws", "alg"], detail: nil}}
  """
  @spec verify_descriptor(term(), nil | DescriptorFacts.t(), Limits.t(), Profile.t()) ::
          {:ok, DescriptorFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_descriptor(compact, predecessor, limits, profile),
    to: PartyDescriptor,
    as: :verify

  @doc """
  Verify every descriptor you hold for one party, in any order.

  `compacts` is a non-empty list of one party's descriptor compacts. Each one
  is verified from genesis forward. Returns
  `{:ok, %CharterAgreementProtocol.DescriptorChain{}}`:

  - `topology` is `:linear` when the descriptors form one line, or `:forked`
    when two signed descriptors share a predecessor.
  - `descriptors` holds one `CharterAgreementProtocol.DescriptorFacts` per
    descriptor, sorted by number. In a linear chain the highest number is
    `:head` and the rest are `:superseded`. In a forked chain every position
    is `:contested`.
  - `fork_evidence` is a `CharterAgreementProtocol.ForkEvidence` for a
    forked chain and `nil` otherwise.

  A fork is a fact, not an error. CAP never picks a winner, and it cannot
  know whether your view is complete.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, chain} = CharterAgreementProtocol.verify_descriptor_chain([hd(set["descriptors"])], limits)
      iex> {chain.topology, length(chain.descriptors), chain.fork_evidence}
      {:linear, 1, nil}
  """
  @spec verify_descriptor_chain(term(), Limits.t()) ::
          {:ok, DescriptorChain.t()} | {:error, CharterAgreementProtocol.Error.t()}
  @spec verify_descriptor_chain(term(), Limits.t(), Profile.t()) ::
          {:ok, DescriptorChain.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_descriptor_chain(compacts, limits), to: DescriptorChain, as: :verify

  @doc """
  Verify one party's descriptors under a capability profile.

  Same as `verify_descriptor_chain/2`, but any descriptor outside `profile`
  fails the call with `:algorithm_outside_profile` or
  `:revision_outside_profile`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(revisions: {1, 3})
      iex> {:ok, chain} = CharterAgreementProtocol.verify_descriptor_chain([hd(set["descriptors"])], limits, profile)
      iex> chain.topology
      :linear
  """
  @spec verify_descriptor_chain(term(), Limits.t(), Profile.t()) ::
          {:ok, DescriptorChain.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_descriptor_chain(compacts, limits, profile),
    to: DescriptorChain,
    as: :verify

  @doc """
  Decode one Charter Revision and check its structure.

  A revision is unsigned. `bytes` is its canonical JSON (RFC 8785): bytes
  that are valid JSON but not canonical fail with `:non_canonical_bytes`.
  Returns `{:ok, %CharterAgreementProtocol.CharterRevision{}}`, which keeps
  the exact bytes in `canonical_bytes`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, revision} = CharterAgreementProtocol.decode_charter_revision(hd(set["revisions"]), limits)
      iex> {revision.revision_number, length(revision.parties)}
      {1, 2}
      iex> CharterAgreementProtocol.decode_charter_revision(~s({"revision_number": 1}), limits)
      {:error, %CharterAgreementProtocol.Error{code: :non_canonical_bytes, subject: ["charter_revision"], detail: nil}}
  """
  @spec decode_charter_revision(term(), Limits.t()) ::
          {:ok, CharterRevision.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate decode_charter_revision(bytes, limits), to: CharterRevision, as: :decode

  @doc """
  Build a Charter Revision's canonical bytes from a plain claims map.

  `claims` uses string keys and plain values: maps, lists, strings,
  integers, floats, booleans and `nil`. Revisions are unsigned canonical
  JSON, so these bytes are what parties accept and what `verify_chain/5`
  takes. The result is decoded under `CharterAgreementProtocol.Limits.default/0`
  before it is returned, so invalid claims fail here with the error a
  verifier would report.

  Returns `{:ok, bytes}` or a typed error.

  ## Examples

  Decoding a shipped revision to a plain map and encoding it again gives back
  the same bytes:

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> bytes = hd(set["revisions"])
      iex> claims = JSON.decode!(bytes)
      iex> CharterAgreementProtocol.encode_charter_revision(claims) == {:ok, bytes}
      true
      iex> CharterAgreementProtocol.encode_charter_revision(Map.delete(claims, "parties"))
      {:error, %CharterAgreementProtocol.Error{code: :missing_required, subject: ["charter_revision", "parties"], detail: nil}}
  """
  @spec encode_charter_revision(map()) ::
          {:ok, binary()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate encode_charter_revision(claims), to: CharterRevision, as: :encode

  @doc """
  Return a decoded Charter Revision's content digest.

  The digest is a `"sha-256:<base64url>"` string. Acceptances name the
  revision they accept by this value. The genesis revision's digest is also
  the charter's id.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, revision} = CharterAgreementProtocol.decode_charter_revision(hd(set["revisions"]), limits)
      iex> CharterAgreementProtocol.revision_digest(revision)
      "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"
  """
  @spec revision_digest(CharterRevision.t()) :: binary()
  defdelegate revision_digest(revision), to: CharterRevision, as: :digest

  @doc """
  Verify one Acceptance against a revision and the signer's descriptor chain.

  `compact` is the Acceptance's compact JWS (`typ` `"cap+acceptance"`).
  `revision` is the decoded revision it accepts, and `descriptor_chain` is
  the signing party's verified chain from `verify_descriptor_chain/2`. The
  claims must match the revision exactly (charter id, revision number and
  digest, previous revision digest, and a party listed in the revision), and
  the signature must come from a key active in the descriptor the claims
  name.

  Returns `{:ok, %CharterAgreementProtocol.AcceptanceFacts{}}`. One
  Acceptance is one party's assent. Whether every party accepted the
  revision is decided by `verify_chain/5`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, revision} = CharterAgreementProtocol.decode_charter_revision(hd(set["revisions"]), limits)
      iex> [issuer_descriptor, acceptor_descriptor] = set["descriptors"]
      iex> [issuer_acceptance, _acceptor_acceptance] = set["acceptances"]
      iex> {:ok, chain} = CharterAgreementProtocol.verify_descriptor_chain([issuer_descriptor], limits)
      iex> {:ok, facts} = CharterAgreementProtocol.verify_acceptance(issuer_acceptance, revision, chain, limits)
      iex> {facts.party_role, facts.descriptor_position}
      {"issuer", :head}
      iex> {:ok, other} = CharterAgreementProtocol.verify_descriptor_chain([acceptor_descriptor], limits)
      iex> CharterAgreementProtocol.verify_acceptance(issuer_acceptance, revision, other, limits)
      {:error, %CharterAgreementProtocol.Error{code: :acceptance_claims_mismatch, subject: ["acceptance", "claims"], detail: nil}}
  """
  @spec verify_acceptance(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t()) ::
          {:ok, AcceptanceFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  @spec verify_acceptance(
          term(),
          CharterRevision.t(),
          DescriptorChain.t(),
          Limits.t(),
          Profile.t()
        ) ::
          {:ok, AcceptanceFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_acceptance(compact, revision, descriptor_chain, limits),
    to: Acceptance,
    as: :verify

  @doc """
  Verify one Acceptance under a capability profile.

  Same as `verify_acceptance/4`, but the profile applies to every artifact
  the call verifies: the supplied revision first, then each descriptor in
  the supplied chain, then the Acceptance. The revision is unsigned, so only
  its `protocol_revision` is checked. Any of them outside `profile` fails
  with `:algorithm_outside_profile` or `:revision_outside_profile`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, revision} = CharterAgreementProtocol.decode_charter_revision(hd(set["revisions"]), limits)
      iex> {:ok, chain} = CharterAgreementProtocol.verify_descriptor_chain([hd(set["descriptors"])], limits)
      iex> {:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(algorithms: ["Ed25519"])
      iex> CharterAgreementProtocol.verify_acceptance(hd(set["acceptances"]), revision, chain, limits, profile)
      {:error, %CharterAgreementProtocol.Error{code: :algorithm_outside_profile, subject: ["compact_jws", "alg"], detail: nil}}
  """
  @spec verify_acceptance(
          term(),
          CharterRevision.t(),
          DescriptorChain.t(),
          Limits.t(),
          Profile.t()
        ) ::
          {:ok, AcceptanceFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_acceptance(compact, revision, descriptor_chain, limits, profile),
    to: Acceptance,
    as: :verify

  @doc """
  Verify one termination notice against a revision and the signer's chain.

  `compact` is the notice's compact JWS (`typ` `"cap+termination"`).
  `revision` is the decoded revision the notice names in
  `governing_revision_digest`, and `descriptor_chain` is the signing party's
  verified chain. The signer must be a party listed in the revision, the
  `reason_code` must be one the revision's `termination_rules` list, and
  `issued_at` must not be after `effective_at`.

  Returns `{:ok, %CharterAgreementProtocol.TerminationFacts{}}`. A verified
  notice ends the charter only if the revision it names is the one that
  governs at its `effective_at`; `governing_revision/2` applies that rule.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/termination-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => input} = Enum.find(cases, &(&1["id"] == "termination-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, revision} = CharterAgreementProtocol.decode_charter_revision(input["revision_text"], limits)
      iex> {:ok, chain} = CharterAgreementProtocol.verify_descriptor_chain(input["descriptor_compacts"], limits)
      iex> {:ok, facts} = CharterAgreementProtocol.verify_termination(input["compact"], revision, chain, limits)
      iex> {facts.party_role, facts.reason_code}
      {"issuer", "mutual"}
  """
  @spec verify_termination(term(), CharterRevision.t(), DescriptorChain.t(), Limits.t()) ::
          {:ok, TerminationFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  @spec verify_termination(
          term(),
          CharterRevision.t(),
          DescriptorChain.t(),
          Limits.t(),
          Profile.t()
        ) ::
          {:ok, TerminationFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_termination(compact, revision, descriptor_chain, limits),
    to: TerminationNotice,
    as: :verify

  @doc """
  Verify one termination notice under a capability profile.

  Same as `verify_termination/4`, but the profile applies to every artifact
  the call verifies: the supplied revision first, then each descriptor in
  the supplied chain, then the notice. The revision is unsigned, so only its
  `protocol_revision` is checked. Any of them outside `profile` fails with
  `:algorithm_outside_profile` or `:revision_outside_profile`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/termination-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => input} = Enum.find(cases, &(&1["id"] == "termination-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, revision} = CharterAgreementProtocol.decode_charter_revision(input["revision_text"], limits)
      iex> {:ok, chain} = CharterAgreementProtocol.verify_descriptor_chain(input["descriptor_compacts"], limits)
      iex> {:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(algorithms: ["Ed25519"])
      iex> CharterAgreementProtocol.verify_termination(input["compact"], revision, chain, limits, profile)
      {:error, %CharterAgreementProtocol.Error{code: :algorithm_outside_profile, subject: ["compact_jws", "alg"], detail: nil}}
  """
  @spec verify_termination(
          term(),
          CharterRevision.t(),
          DescriptorChain.t(),
          Limits.t(),
          Profile.t()
        ) ::
          {:ok, TerminationFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_termination(compact, revision, descriptor_chain, limits, profile),
    to: TerminationNotice,
    as: :verify

  @doc """
  Verify one receipt against chain facts or a single revision.

  `compact` is the receipt's compact JWS (`typ` `"cap+receipt"`). The
  `context` decides how much CAP can check:

  - With `CharterAgreementProtocol.ChainFacts` from `verify_chain/5`, CAP
    verifies the retained artifact set again, checks the issuing party's
    signature against the descriptors of accepted revisions, and compares
    the receipt's revision with the one governing at its `occurred_at`.
  - With a decoded `CharterAgreementProtocol.CharterRevision` alone, CAP
    checks the claims against that revision but cannot find the signer's
    key. The facts then add `:signature` to `not_verified`, set
    `signing_key_id` to `nil`, and report `governing_match: :undetermined`.

  Returns `{:ok, %CharterAgreementProtocol.ReceiptFacts{}}`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/receipt-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => %{"chain" => set, "compact" => receipt}} =
      ...>   Enum.find(cases, &(&1["id"] == "receipt-signed-governing-match"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, chain} =
      ...>   CharterAgreementProtocol.verify_chain(
      ...>     set["revisions"],
      ...>     set["acceptances"],
      ...>     set["descriptors"],
      ...>     set["terminations"],
      ...>     limits
      ...>   )
      iex> {:ok, facts} = CharterAgreementProtocol.verify_receipt(receipt, chain, limits)
      iex> {facts.governing_match, facts.chain_conflict, facts.outcome}
      {:match, :none, :effect_committed}
  """
  @spec verify_receipt(term(), ChainFacts.t() | CharterRevision.t(), Limits.t()) ::
          {:ok, ReceiptFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  @spec verify_receipt(
          term(),
          ChainFacts.t() | CharterRevision.t(),
          Limits.t(),
          Profile.t()
        ) ::
          {:ok, ReceiptFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_receipt(compact, context, limits), to: Receipt, as: :verify

  @doc """
  Verify one receipt under a capability profile.

  Same as `verify_receipt/3`, but the profile applies to every artifact the
  call verifies, context first, then the receipt:

  - With `CharterAgreementProtocol.ChainFacts`, the retained artifact set is
    verified again under `profile`, as `verify_chain/6` does.
  - With a bare `CharterAgreementProtocol.CharterRevision`, the revision's
    `protocol_revision` is checked, and the receipt's envelope (its `alg` and
    `protocol_revision`) is admitted against `profile` even though its
    signature stays unchecked
    (`:signature` remains in `not_verified`).

  Any artifact outside `profile` fails with `:algorithm_outside_profile` or
  `:revision_outside_profile`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/receipt-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => %{"chain" => set, "compact" => receipt}} =
      ...>   Enum.find(cases, &(&1["id"] == "receipt-signed-governing-match"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, chain} =
      ...>   CharterAgreementProtocol.verify_chain(
      ...>     set["revisions"],
      ...>     set["acceptances"],
      ...>     set["descriptors"],
      ...>     set["terminations"],
      ...>     limits
      ...>   )
      iex> {:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(algorithms: ["Ed25519"])
      iex> CharterAgreementProtocol.verify_receipt(receipt, chain, limits, profile)
      {:error, %CharterAgreementProtocol.Error{code: :algorithm_outside_profile, subject: ["compact_jws", "alg"], detail: nil}}
  """
  @spec verify_receipt(
          term(),
          ChainFacts.t() | CharterRevision.t(),
          Limits.t(),
          Profile.t()
        ) ::
          {:ok, ReceiptFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_receipt(compact, context, limits, profile), to: Receipt, as: :verify

  @doc """
  Build the bytes to sign for a Party Descriptor.

  `input` is `%{"kid" => kid, "claims" => claims}`, with an optional
  `"algorithm"` member: `"Ed25519"` (the default) or `"ML-DSA-65"`. `kid` is
  the signing key's id, 1 to 128 characters from `A-Z a-z 0-9 - . _ ~`.
  `claims` is the descriptor's claims as a plain map with string keys. Its
  `protocol_revision` must be 2 for `"Ed25519"` or 3 for `"ML-DSA-65"`.

  Returns `{:ok, %CharterAgreementProtocol.SigningInput{}}`. Sign its
  `message` bytes with your key, then pass the signature to
  `assemble_compact/2`. Any other input returns `:signing_input_invalid`.
  This function never signs.

  ## Examples

  The whole flow, with signing done by your own code outside CAP
  (`sign_externally` stands for your key store or HSM call):

      {:ok, input} =
        CharterAgreementProtocol.descriptor_signing_input(%{"kid" => "key-1", "claims" => claims})

      signature = sign_externally.(input.message)
      {:ok, compact} = CharterAgreementProtocol.assemble_compact(input, signature)

      {:ok, _facts} =
        CharterAgreementProtocol.verify_descriptor(compact, nil, CharterAgreementProtocol.Limits.default())

  The `charter_agreement_signer` package does these steps for you.

  Building the signing input on its own:

      iex> claims = %{
      ...>   "attestation_hints" => [],
      ...>   "descriptor_number" => 1,
      ...>   "effective_from" => "2026-10-01T00:00:00Z",
      ...>   "extensions" => %{"critical" => %{}, "optional" => %{}},
      ...>   "protocol_revision" => 2,
      ...>   "verification_keys" => [
      ...>     %{
      ...>       "algorithm" => "Ed25519",
      ...>       "key_id" => "key-1",
      ...>       "public_key" => CharterAgreementProtocol.Base64Url.encode(:binary.copy(<<1>>, 32)),
      ...>       "status" => "active"
      ...>     }
      ...>   ]
      ...> }
      iex> {:ok, input} = CharterAgreementProtocol.descriptor_signing_input(%{"kid" => "key-1", "claims" => claims})
      iex> {input.kind, input.alg}
      {:party_descriptor, "Ed25519"}
      iex> input.message == input.protected_segment <> "." <> input.payload_segment
      true

  Claims at the wrong protocol revision for the algorithm are refused:

      iex> claims = %{"protocol_revision" => 1}
      iex> CharterAgreementProtocol.descriptor_signing_input(%{"kid" => "key-1", "claims" => claims})
      {:error, %CharterAgreementProtocol.Error{code: :signing_input_invalid, subject: ["signing_input"], detail: nil}}
  For the holder's descriptor key check before signing, use `prepare_signing/5`
  and `finish_signing/2` with explicit limits and profile.
  """
  @spec descriptor_signing_input(term()) ::
          {:ok, SigningInput.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate descriptor_signing_input(input), to: SigningInput, as: :descriptor

  @doc """
  Build the bytes to sign for a receipt.

  `input` has the same shape as for `descriptor_signing_input/1`:
  `%{"kid" => kid, "claims" => claims}` plus an optional `"algorithm"`. The
  claims' `protocol_revision` must be 2 for `"Ed25519"` (the default) or 3
  for `"ML-DSA-65"`. The claims are checked as a receipt, not against a
  charter: verify the assembled receipt with `verify_receipt/3`.

  Returns `{:ok, %CharterAgreementProtocol.SigningInput{}}` or
  `:signing_input_invalid`. This function never signs.

  ## Examples

      iex> CharterAgreementProtocol.receipt_signing_input(%{"kid" => "key-1", "claims" => %{}})
      {:error, %CharterAgreementProtocol.Error{code: :signing_input_invalid, subject: ["signing_input"], detail: nil}}
  For the holder's descriptor key check before signing, use `prepare_signing/5`
  and `finish_signing/2` with explicit limits and profile.
  """
  @spec receipt_signing_input(term()) ::
          {:ok, SigningInput.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate receipt_signing_input(input), to: SigningInput, as: :receipt

  @doc """
  Build the bytes to sign for an Acceptance, after checking it against a set.

  `input` has the same shape as for `descriptor_signing_input/1`, and the
  claims' `protocol_revision` must be 2 for `"Ed25519"` (the default) or 3
  for `"ML-DSA-65"`. `set` comes from `build_set/4` and holds the artifacts
  the signer has. CAP verifies the set under default limits, then refuses
  with `:signing_refused` when:

  - the claims do not match a revision in the set (charter id, revision
    number, previous revision digest, and a listed party's role and
    descriptor digest);
  - the set already has an Acceptance of a different revision with the same
    charter and revision number;
  - the revision does not descend from, or supersede, every highest accepted
    revision in the set.

  These checks keep a signer from signing something wrong in the set it
  holds. They cannot stop a signer who means to cheat, and they cannot know
  whether the set is complete. Returns `{:ok, %CharterAgreementProtocol.SigningInput{}}`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> {:ok, proposed} = CharterAgreementProtocol.build_set(set["revisions"], [], [], set["descriptors"])
      iex> revision = "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"
      iex> claims = %{
      ...>   "accepted_at" => "2026-08-25T13:00:00Z",
      ...>   "charter_id" => revision,
      ...>   "party_descriptor_digest" => "sha-256:eA2wh9rHIu1R6AOrpOULW4BRKEJcD4m9S2LA5-24KqY",
      ...>   "party_role" => "acceptor",
      ...>   "protocol_revision" => 2,
      ...>   "revision_digest" => revision,
      ...>   "revision_number" => 1
      ...> }
      iex> {:ok, input} = CharterAgreementProtocol.acceptance_signing_input(%{"kid" => "acceptor-key", "claims" => claims}, proposed)
      iex> {input.kind, input.alg}
      {:acceptance, "Ed25519"}
      iex> wrong_role = Map.put(claims, "party_role", "issuer")
      iex> CharterAgreementProtocol.acceptance_signing_input(%{"kid" => "acceptor-key", "claims" => wrong_role}, proposed)
      {:error, %CharterAgreementProtocol.Error{code: :signing_refused, subject: ["signing_input", "claims"], detail: nil}}
  For the holder's descriptor key check before signing, use `prepare_signing/5`
  and `finish_signing/2` with explicit limits and profile.
  """
  @spec acceptance_signing_input(term(), ArtifactSet.t()) ::
          {:ok, SigningInput.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate acceptance_signing_input(input, set), to: SigningInput, as: :acceptance

  @doc """
  Build the bytes to sign for a termination notice, after checking it
  against a set.

  `input` has the same shape as for `descriptor_signing_input/1`, and the
  claims' `protocol_revision` must be 2 for `"Ed25519"` (the default) or 3
  for `"ML-DSA-65"`. `set` comes from `build_set/4`. CAP verifies the set
  under default limits, then refuses with `:signing_refused` unless the
  revision the claims name is in the set, the charter id matches, the
  `reason_code` is listed in that revision's `termination_rules`, the role
  and descriptor digest match a listed party, and that revision is the one
  that governs at the notice's `effective_at`.

  These checks keep a signer from signing something wrong in the set it
  holds.
  Returns `{:ok, %CharterAgreementProtocol.SigningInput{}}`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> {:ok, accepted} = CharterAgreementProtocol.build_set(set["revisions"], set["acceptances"], [], set["descriptors"])
      iex> revision = "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"
      iex> claims = %{
      ...>   "charter_id" => revision,
      ...>   "effective_at" => "2026-09-01T00:00:00Z",
      ...>   "governing_revision_digest" => revision,
      ...>   "issued_at" => "2026-08-30T00:00:00Z",
      ...>   "party_descriptor_digest" => "sha-256:1ynn3VZQs_pAZVjrnDn-DzEUMc8gJV0FMFV3SFONZIU",
      ...>   "party_role" => "issuer",
      ...>   "protocol_revision" => 2,
      ...>   "reason_code" => "mutual"
      ...> }
      iex> {:ok, input} = CharterAgreementProtocol.termination_signing_input(%{"kid" => "genesis-key", "claims" => claims}, accepted)
      iex> input.kind
      :termination
      iex> {:ok, proposed} = CharterAgreementProtocol.build_set(set["revisions"], [], [], set["descriptors"])
      iex> CharterAgreementProtocol.termination_signing_input(%{"kid" => "genesis-key", "claims" => claims}, proposed)
      {:error, %CharterAgreementProtocol.Error{code: :signing_refused, subject: ["signing_input", "claims"], detail: nil}}
  For the holder's descriptor key check before signing, use `prepare_signing/5`
  and `finish_signing/2` with explicit limits and profile.
  """
  @spec termination_signing_input(term(), ArtifactSet.t()) ::
          {:ok, SigningInput.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate termination_signing_input(input, set), to: SigningInput, as: :termination

  @doc """
  Join a signing input and its raw signature into a compact JWS.

  `input` is a `CharterAgreementProtocol.SigningInput` from one of the
  signing-input functions. `signature` is the raw signature over
  `input.message`, at the exact length for the input's algorithm: 64 bytes
  for `"Ed25519"` or 3309 bytes for `"ML-DSA-65"`, the only two algorithms
  CAP builds signing inputs for.

  Returns `{:ok, compact}`. A signature of the wrong length returns
  `:signature_invalid`, and an altered signing input returns
  `:signing_input_invalid`. This function checks lengths and structure, not
  the signature itself, so verify the compact before you use it. See
  `descriptor_signing_input/1` for a full example.

  ## Examples

      iex> claims = %{
      ...>   "attestation_hints" => [],
      ...>   "descriptor_number" => 1,
      ...>   "effective_from" => "2026-10-01T00:00:00Z",
      ...>   "extensions" => %{"critical" => %{}, "optional" => %{}},
      ...>   "protocol_revision" => 2,
      ...>   "verification_keys" => [
      ...>     %{
      ...>       "algorithm" => "Ed25519",
      ...>       "key_id" => "key-1",
      ...>       "public_key" => CharterAgreementProtocol.Base64Url.encode(:binary.copy(<<1>>, 32)),
      ...>       "status" => "active"
      ...>     }
      ...>   ]
      ...> }
      iex> {:ok, input} = CharterAgreementProtocol.descriptor_signing_input(%{"kid" => "key-1", "claims" => claims})
      iex> CharterAgreementProtocol.assemble_compact(input, :binary.copy(<<0>>, 63))
      {:error, %CharterAgreementProtocol.Error{code: :signature_invalid, subject: ["compact_jws", "signature"], detail: nil}}
  """
  @spec assemble_compact(term(), term()) ::
          {:ok, binary()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate assemble_compact(input, signature), to: SigningInput, as: :assemble

  @doc """
  Collect raw artifacts into a set without verifying them.

  The argument order is revisions, acceptances, terminations, descriptors.
  This differs from `verify_chain/5`, which takes descriptors before
  terminations. Each argument is a list of binaries: revision bytes and
  compact JWS strings. The set keeps the order you give.

  Returns `{:ok, %CharterAgreementProtocol.ArtifactSet{}}`, which you pass to
  `acceptance_signing_input/2` or `termination_signing_input/2`, or
  `:invalid_type` when any argument is not a list of binaries.

  ## Examples

      iex> {:ok, set} = CharterAgreementProtocol.build_set(["revision bytes"], [], [], ["descriptor compact"])
      iex> set
      #CharterAgreementProtocol.ArtifactSet<redacted>
      iex> CharterAgreementProtocol.build_set(["revision bytes"], [], [], [:not_a_binary])
      {:error, %CharterAgreementProtocol.Error{code: :invalid_type, subject: ["artifact_set"], detail: nil}}
  """
  @spec build_set(term(), term(), term(), term()) ::
          {:ok, ArtifactSet.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate build_set(revisions, acceptances, terminations, descriptors),
    to: ArtifactSet,
    as: :build

  @doc """
  Report which signature algorithms this runtime can verify.

  Returns a map with two keys:

  - `:algorithms` has one entry per algorithm in the registry, each with
    `:name`, `:key_algorithm` and `:verifiable`. `:verifiable` is `true` only
    when the runtime declares the algorithm and a pinned test vector actually
    verifies.
  - `:linked_crypto` is `:crypto.info_lib/0`, for your logs. It does not
    affect the result.

  Call it at boot to decide what your deployment supports. Each verify call
  still checks on its own and returns `:algorithm_unsupported_on_substrate`
  when the runtime cannot verify an artifact's algorithm.

  ## Examples

      iex> report = CharterAgreementProtocol.capabilities()
      iex> Enum.map(report.algorithms, & &1.name)
      ["EdDSA", "Ed25519", "ML-DSA-44", "ML-DSA-65", "ML-DSA-87"]
      iex> Enum.find(report.algorithms, &(&1.name == "Ed25519")).verifiable
      true
  """
  @spec capabilities() :: CharterAgreementProtocol.Capability.report()
  defdelegate capabilities(), to: CharterAgreementProtocol.Capability, as: :report

  @doc """
  Verify a complete charter artifact set.

  The argument order is revisions, acceptances, descriptors, terminations,
  limits. This differs from `build_set/4`, which takes terminations before
  descriptors. Each list holds binaries: revision bytes, and compact JWS
  strings for the rest.

  The set must hold at least one revision, exactly one genesis revision
  (`revision_number` 1), and every revision for the same charter. The
  descriptors must cover exactly two parties. Every Acceptance and
  termination notice must name a revision and a descriptor in the set.
  Before any decoding, each list must fit `max_artifact_set_items` and the
  total bytes must fit `max_artifact_set_bytes`.

  Returns `{:ok, %CharterAgreementProtocol.ChainFacts{}}`. Signed conflicts,
  such as two accepted revisions with the same number, come back as
  `fork_evidence` and `chain_topology: :forked`, not as errors.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> limits = CharterAgreementProtocol.Limits.default()
      iex> {:ok, facts} =
      ...>   CharterAgreementProtocol.verify_chain(
      ...>     set["revisions"],
      ...>     set["acceptances"],
      ...>     set["descriptors"],
      ...>     set["terminations"],
      ...>     limits
      ...>   )
      iex> facts
      #CharterAgreementProtocol.ChainFacts<redacted>
      iex> {facts.charter_id, facts.fork_evidence}
      {"sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o", []}
      iex> CharterAgreementProtocol.verify_chain([], [], [], [], limits)
      {:error, %CharterAgreementProtocol.Error{code: :chain_invalid, subject: ["chain"], detail: nil}}
  """
  @spec verify_chain(term(), term(), term(), term(), Limits.t()) ::
          {:ok, ChainFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  @spec verify_chain(term(), term(), term(), term(), Limits.t(), Profile.t()) ::
          {:ok, ChainFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_chain(revisions, acceptances, descriptors, terminations, limits),
    to: Chain,
    as: :verify

  @doc """
  Verify a complete charter artifact set under a capability profile.

  Same as `verify_chain/5`, with the same argument order. The profile
  narrows which `alg` names and `protocol_revision` values you accept, per
  artifact, before any signature work. An artifact outside it fails with
  `:algorithm_outside_profile` or `:revision_outside_profile`, and a
  malformed profile fails with `:invalid_profile`.

  ## Examples

  The shipped set is signed with the older `"EdDSA"` name, so a profile that
  accepts only `"Ed25519"` rejects it:

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> {:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(algorithms: ["Ed25519"])
      iex> CharterAgreementProtocol.verify_chain(
      ...>   set["revisions"],
      ...>   set["acceptances"],
      ...>   set["descriptors"],
      ...>   set["terminations"],
      ...>   CharterAgreementProtocol.Limits.default(),
      ...>   profile
      ...> )
      {:error, %CharterAgreementProtocol.Error{code: :algorithm_outside_profile, subject: ["compact_jws", "alg"], detail: nil}}
  """
  @spec verify_chain(term(), term(), term(), term(), Limits.t(), Profile.t()) ::
          {:ok, ChainFacts.t()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate verify_chain(revisions, acceptances, descriptors, terminations, limits, profile),
    to: Chain,
    as: :verify

  @doc """
  Find the revision that governs at one instant.

  `chain_facts` comes from `verify_chain/5`. `at` is the instant you ask
  about, as a UTC `DateTime` or a `CharterAgreementProtocol.Timestamp`. CAP
  never reads a clock, so pass the current time yourself when that is what
  you mean.

  A revision is a candidate at `at` when every party accepted it, no
  accepted revision supersedes it, and `effective_from <= at` (and
  `at < effective_until` when it has an end). Returns:

  - `{:ok, digest}` when one candidate is the newest and every other
    candidate is its ancestor. `digest` is a `"sha-256:<base64url>"` string.
  - `{:ok, :contested}` when the candidates do not form one line, for
    example two accepted revisions with the same number.
  - `{:ok, :none}` when there is no candidate, or a verified termination
    notice that named the then-governing revision took effect at or before
    `at`.

  A `DateTime` in another time zone returns `:governing_invalid`. Any other
  type returns `:invalid_type`.

  ## Examples

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/chain-verify.json")
      iex> %{"cases" => cases} = file |> File.read!() |> JSON.decode!()
      iex> %{"input" => set} = Enum.find(cases, &(&1["id"] == "chain-dual-acceptance-valid"))
      iex> {:ok, facts} =
      ...>   CharterAgreementProtocol.verify_chain(
      ...>     set["revisions"],
      ...>     set["acceptances"],
      ...>     set["descriptors"],
      ...>     set["terminations"],
      ...>     CharterAgreementProtocol.Limits.default()
      ...>   )
      iex> CharterAgreementProtocol.governing_revision(facts, ~U[2026-09-01 00:00:00Z])
      {:ok, "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"}
      iex> CharterAgreementProtocol.governing_revision(facts, ~U[2026-08-25 11:00:00Z])
      {:ok, :none}
      iex> {:ok, at} = CharterAgreementProtocol.Timestamp.parse("2026-09-01T00:00:00Z")
      iex> CharterAgreementProtocol.governing_revision(facts, at)
      {:ok, "sha-256:j9vaSLLwxMwF1zzLniUdZwUUAB6aTGEvwMRzP526s3o"}
  """
  @spec governing_revision(term(), term()) ::
          {:ok, binary() | :contested | :none} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate governing_revision(chain_facts, at), to: Chain

  @doc """
  Check an input before external signing under explicit limits and profile.

  The closed input contains `"kid"`, `"claims"`, raw `"public_key"` bytes
  and optionally `"algorithm"`. Kinds are `:party_descriptor`, `:acceptance`,
  `:termination` and `:receipt`. Descriptor context is nil or predecessor
  facts. Acceptance and termination context is an `ArtifactSet`. Receipt
  context is `ChainFacts` or a bare `CharterRevision`.

  Checks run in this order: limits, profile, context type, input build, key
  shape, set verification and producer refusals, verification preparation,
  snapshot membership, runtime support. Limits bound the whole set read.
  Set verification uses the full caller profile. A bare revision receipt
  returns `key: :unnamed`; every other successful plan has `key: :matched`.

  Sign the returned `signing_input.message`, then call `finish_signing/2`.
  CAP holds only public verification material and never signs.

  ## Examples

      iex> CharterAgreementProtocol.prepare_signing(:receipt, %{}, nil,
      ...>   CharterAgreementProtocol.Limits.default(), CharterAgreementProtocol.Capability.Profile.full())
      {:error, %CharterAgreementProtocol.Error{code: :invalid_type, subject: ["signing_plan"], detail: nil}}

      iex> file = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/party_descriptor-verify.json")
      iex> cases = File.read!(file) |> JSON.decode!() |> Map.fetch!("cases")
      iex> compact = Enum.find(cases, &(&1["id"] == "descriptor-rev2-ed25519-valid"))["input"]["compact"]
      iex> {:ok, descriptor} = CharterAgreementProtocol.PartyDescriptor.decode(compact, CharterAgreementProtocol.Limits.default())
      iex> claims = JSON.decode!(descriptor.envelope.payload_bytes)
      iex> input = %{"kid" => descriptor.envelope.kid, "claims" => claims, "public_key" => hd(descriptor.verification_keys).public_key}
      iex> {:ok, plan} = CharterAgreementProtocol.prepare_signing(:party_descriptor, input, nil, CharterAgreementProtocol.Limits.default(), CharterAgreementProtocol.Capability.Profile.full())
      iex> {plan.key, plan.signing_input.message == descriptor.envelope.message}
      {:matched, true}
      iex> CharterAgreementProtocol.finish_signing(plan, descriptor.envelope.signature) == {:ok, compact}
      true
  """
  @spec prepare_signing(
          CharterAgreementProtocol.SigningInput.kind(),
          term(),
          term(),
          Limits.t(),
          Profile.t()
        ) ::
          {:ok, CharterAgreementProtocol.SigningPlan.t()}
          | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate prepare_signing(kind, input, context, limits, profile),
    to: CharterAgreementProtocol.SigningPlan,
    as: :prepare

  @doc """
  Assemble a signature under the plan's limits and run public verification
  with its CAP-derived context and profile. Returns the verified compact.
  Keep the plan's internal fields as returned by `prepare_signing/5`.

  ## Examples

      iex> CharterAgreementProtocol.finish_signing(nil, <<>>)
      {:error, %CharterAgreementProtocol.Error{code: :invalid_type, subject: ["signing_plan"], detail: nil}}
  """
  @spec finish_signing(CharterAgreementProtocol.SigningPlan.t(), binary()) ::
          {:ok, binary()} | {:error, CharterAgreementProtocol.Error.t()}
  defdelegate finish_signing(plan, signature),
    to: CharterAgreementProtocol.SigningPlan,
    as: :finish
end
