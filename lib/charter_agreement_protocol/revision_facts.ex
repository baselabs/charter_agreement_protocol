defmodule CharterAgreementProtocol.RevisionFacts do
  @moduledoc """
  Facts about one Charter Revision inside a verified set. They are
  non-authorizing. `acceptance_status: :accepted` records that the verified
  acceptances and predecessor meet the applicable rules. Legacy revisions
  require both parties' assent. Revision 8 checks quorum and any required
  assignment assent.

  You find these in `CharterAgreementProtocol.ChainFacts.revision_facts`.

  ## Fields

  - `revision`: the decoded `CharterAgreementProtocol.CharterRevision`. Its
    `canonical_bytes` are the exact bytes you supplied.
  - `revision_digest`: the revision's content digest.
  - `charter_id`: the charter's id. For the genesis revision this is its own
    digest; later revisions carry it in their `charter_id` member.
  - `revision_number`: the revision's number, starting at 1.
  - `prev_revision_digest`: the digest of the revision before it, or `nil`
    for the genesis revision.
  - `optional_extensions_retained`: names of every optional extension the
    revision carries, each kept byte for byte. A registered, active namespace
    was validated against its schema; an unknown, reserved or retired one is
    kept without validation, so a name here does not prove registration.
  - `acceptance_facts`: the `CharterAgreementProtocol.AcceptanceFacts` for
    Acceptances of this revision.
  - `acceptance_digests`: the digests of those Acceptances, sorted.
  - `acceptance_status`: `:accepted` when the applicable quorum and assent
    rules are met and the revision is eligible, otherwise `:proposed`.
  - `signature_status`: quorum and assent status before predecessor eligibility.
  - `assignment_status`: `:none`, `:pending`, or `:accepted`.
  - `missing_assent_roles`: sorted roles still owing a signature on the assignment.
  - `protocol_revision`: the revision's `protocol_revision` member.
  - `alg`: always `nil`. Revisions are unsigned; the algorithm names live on
    the Acceptances.
  - `not_verified`: the twelve atoms from
    `CharterAgreementProtocol.Facts.not_verified_floor/0`: `:tenancy`,
    `:live_policy`, `:authority`, `:effect_ownership`, `:execution`,
    `:billing`, `:evaluation_truth`, `:legal_validity`, `:term_satisfaction`,
    `:view_completeness`, `:counterparty_view` and `:wall_clock`.

  Digests are `"sha-256:<base64url>"` strings.

  ## Inspecting

  `inspect/2` prints `#CharterAgreementProtocol.RevisionFacts<redacted>`.
  Read fields directly, or use `inspect(facts, structs: false)` while
  debugging.
  """

  alias CharterAgreementProtocol.{AcceptanceFacts, CharterRevision}

  defstruct [
    :revision,
    :revision_digest,
    :charter_id,
    :revision_number,
    :prev_revision_digest,
    optional_extensions_retained: [],
    acceptance_facts: [],
    acceptance_digests: [],
    acceptance_status: :proposed,
    signature_status: :proposed,
    assignment_status: :none,
    missing_assent_roles: [],
    protocol_revision: nil,
    alg: nil,
    not_verified: []
  ]

  @typedoc "Facts for one revision in a verified set. See the module doc for each field."
  @type t :: %__MODULE__{
          revision: CharterRevision.t(),
          protocol_revision: pos_integer() | nil,
          alg: binary() | nil,
          revision_digest: binary(),
          charter_id: binary(),
          revision_number: pos_integer(),
          prev_revision_digest: nil | binary(),
          optional_extensions_retained: [binary()],
          acceptance_facts: [AcceptanceFacts.t()],
          acceptance_digests: [binary()],
          acceptance_status: :proposed | :accepted,
          signature_status: :proposed | :accepted,
          assignment_status: :none | :pending | :accepted,
          missing_assent_roles: [binary()],
          not_verified: [atom()]
        }
end

defimpl Inspect, for: CharterAgreementProtocol.RevisionFacts do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.RevisionFacts<redacted>")
end
