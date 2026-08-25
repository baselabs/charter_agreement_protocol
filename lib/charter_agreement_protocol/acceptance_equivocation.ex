defmodule CharterAgreementProtocol.AcceptanceEquivocation do
  @moduledoc "Non-authorizing evidence of same-signer countersignatures over different revisions."

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
