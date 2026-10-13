defmodule CharterAgreementProtocol.DescriptorFacts do
  @moduledoc """
  Facts about one verified Party Descriptor: a party's signed key record.
  They are non-authorizing. A verified descriptor chain shows that each key
  set was signed by a key from the one before; it says nothing about who the
  party is.

  `CharterAgreementProtocol.verify_descriptor/3` returns one of these, and
  each `CharterAgreementProtocol.DescriptorChain` holds one per descriptor.

  ## Fields

  - `descriptor`: the decoded `CharterAgreementProtocol.PartyDescriptor`.
  - `descriptor_digest`: the descriptor's content digest. Revisions,
    Acceptances and termination notices name a descriptor by this value.
  - `party_id`: the party's id, which is the genesis descriptor's digest. It
    stays the same along the chain.
  - `descriptor_number`: the descriptor's number, starting at 1.
  - `prev_descriptor_digest`: the digest of the descriptor before it, or
    `nil` at genesis.
  - `signing_key_id`: the `kid` of the key that signed it. At genesis that
    key is in the descriptor itself; later, it is active in the predecessor.
  - `descriptor_position`: `:head` from `verify_descriptor/3`. In a
    `CharterAgreementProtocol.DescriptorChain` it is `:head` for the newest
    descriptor of a linear chain, `:superseded` for older ones, and
    `:contested` for every descriptor of a forked chain.
  - `optional_extensions_retained`: names of every optional extension the
    descriptor carries, each kept byte for byte. A registered, active namespace
    was validated against its schema; an unknown, reserved or retired one is
    kept without validation, so a name here does not prove registration.
  - `lineage`: the raw compacts from this descriptor back to genesis, newest
    first. When you pass these facts as a predecessor, CAP verifies this
    lineage again rather than trusting the struct.
  - `protocol_revision`: the descriptor's `protocol_revision`.
  - `alg`: the JWS `alg` it was signed with, such as `"Ed25519"`.
  - `not_verified`: the twelve atoms from
    `CharterAgreementProtocol.Facts.not_verified_floor/0`: `:tenancy`,
    `:live_policy`, `:authority`, `:effect_ownership`, `:execution`,
    `:billing`, `:evaluation_truth`, `:legal_validity`, `:term_satisfaction`,
    `:view_completeness`, `:counterparty_view` and `:wall_clock`.

  Digests are `"sha-256:<base64url>"` strings.

  ## Inspecting

  `inspect/2` prints `#CharterAgreementProtocol.DescriptorFacts<redacted>`.
  Read fields directly, or use `inspect(facts, structs: false)` while
  debugging.
  """

  @enforce_keys [
    :descriptor,
    :descriptor_digest,
    :party_id,
    :descriptor_number,
    :prev_descriptor_digest,
    :signing_key_id,
    :descriptor_position,
    :optional_extensions_retained,
    :lineage,
    :not_verified
  ]
  defstruct @enforce_keys ++ [protocol_revision: nil, alg: nil]

  @typedoc "Where a descriptor sits in its party's verified chain."
  @type position :: :head | :superseded | :contested
  @typedoc "Facts for one verified Party Descriptor. See the module doc for each field."
  @type t :: %__MODULE__{
          descriptor: CharterAgreementProtocol.PartyDescriptor.t(),
          descriptor_digest: binary(),
          party_id: binary(),
          descriptor_number: pos_integer(),
          prev_descriptor_digest: nil | binary(),
          signing_key_id: binary(),
          descriptor_position: position(),
          optional_extensions_retained: [binary()],
          lineage: [binary()],
          not_verified: [atom()],
          protocol_revision: pos_integer() | nil,
          alg: binary() | nil
        }
end

defimpl Inspect, for: CharterAgreementProtocol.DescriptorFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.DescriptorFacts<redacted>")
end

defmodule CharterAgreementProtocol.ForkEvidence do
  @moduledoc """
  Evidence of a signed conflict in the set you verified. It is
  non-authorizing: CAP reports the conflict and never picks a winner.

  You find these in `CharterAgreementProtocol.ChainFacts.fork_evidence` and
  `CharterAgreementProtocol.DescriptorChain.fork_evidence`.

  ## Fields

  - `kind`: which conflict this is.
    - `:sibling_descriptors`: two or more signed descriptors of one party
      name the same predecessor.
    - `:sibling_revisions`: two or more accepted revisions share a revision
      number.
    - `:equivocal_acceptances`: one party, under one descriptor and role,
      accepted different revisions with the same charter and revision
      number.
  - `sibling_descriptors`: for `:sibling_descriptors`, the digests of the
    competing descriptors, sorted. Empty otherwise.
  - `revision_digests`: for `:sibling_revisions` and `:equivocal_acceptances`,
    the digests of the competing revisions, sorted. Empty otherwise.
  - `acceptance_digests`: for `:equivocal_acceptances`, the digests of the
    competing Acceptances, sorted. Empty otherwise.
  - `not_verified`: the twelve atoms from
    `CharterAgreementProtocol.Facts.not_verified_floor/0`: `:tenancy`,
    `:live_policy`, `:authority`, `:effect_ownership`, `:execution`,
    `:billing`, `:evaluation_truth`, `:legal_validity`, `:term_satisfaction`,
    `:view_completeness`, `:counterparty_view` and `:wall_clock`.

  Digests are `"sha-256:<base64url>"` strings. When accepted sibling
  revisions are the newest candidates at an instant,
  `CharterAgreementProtocol.governing_revision/2` returns `:contested`.

  ## Inspecting

  `inspect/2` prints `#CharterAgreementProtocol.ForkEvidence<redacted>`.
  Read fields directly, or use `inspect(evidence, structs: false)` while
  debugging.
  """

  @enforce_keys [:kind, :not_verified]
  defstruct [
    :kind,
    sibling_descriptors: [],
    revision_digests: [],
    acceptance_digests: [],
    not_verified: []
  ]

  @typedoc "One signed conflict. See the module doc for each field."
  @type t :: %__MODULE__{
          kind: :sibling_descriptors | :sibling_revisions | :equivocal_acceptances,
          sibling_descriptors: [binary()],
          revision_digests: [binary()],
          acceptance_digests: [binary()],
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.ForkEvidence do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.ForkEvidence<redacted>")
end
