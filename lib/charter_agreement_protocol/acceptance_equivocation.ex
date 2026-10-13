defmodule CharterAgreementProtocol.AcceptanceEquivocation do
  @moduledoc """
  A summary of evidence that one signer accepted two different revisions in
  the same slot. It is non-authorizing and holds digests and coordinates
  only, not the Acceptances or their signatures: keep the two Acceptances
  themselves to show the equivocation to anyone else. `winner` is always
  `nil`, because CAP never chooses between them.

  `CharterAgreementProtocol.Acceptance.equivocation/2` returns one of these
  for two `CharterAgreementProtocol.AcceptanceFacts` that share charter id,
  revision number, descriptor digest and role but accept different
  revisions.

  This is not a facts record. It is not built by
  `CharterAgreementProtocol.Facts`, has no `not_verified` list, and prints
  normally with `inspect/2`.

  ## Fields

  - `kind`: always `:acceptance_equivocation`.
  - `charter_id`: the charter both Acceptances name.
  - `revision_number`: the revision number both Acceptances name.
  - `party_descriptor_digest`: the signer's descriptor digest.
  - `party_role`: the signer's role.
  - `acceptance_digests`: the two Acceptance digests, sorted.
  - `revision_digests`: the two accepted revision digests, sorted.
  - `winner`: always `nil`.

  Digests are `"sha-256:<base64url>"` strings.
  """

  @enforce_keys [
    :kind,
    :charter_id,
    :revision_number,
    :party_descriptor_digest,
    :party_role,
    :acceptance_digests,
    :revision_digests,
    :winner
  ]
  defstruct @enforce_keys

  @typedoc "Equivocation evidence for one signer. See the module doc for each field."
  @type t :: %__MODULE__{
          kind: :acceptance_equivocation,
          charter_id: binary(),
          revision_number: pos_integer(),
          party_descriptor_digest: binary(),
          party_role: binary(),
          acceptance_digests: [binary()],
          revision_digests: [binary()],
          winner: nil
        }
end
