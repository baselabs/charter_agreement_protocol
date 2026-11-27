defmodule CharterAgreementProtocol.ReceiptInspection do
  @moduledoc """
  CAP never authorizes.

  Portable evidence returned by `CharterAgreementProtocol.inspect_receipt/4`.
  The signed segments reproduce the entire input compact when joined with
  periods. The comparisons describe the caller's retained grant and chain view.
  """

  alias CharterAgreementProtocol.{
    Chain,
    ChainFacts,
    Digest,
    Error,
    Facts,
    PartyDescriptor,
    Receipt
  }

  @type json_value ::
          nil
          | boolean()
          | number()
          | binary()
          | [json_value()]
          | %{optional(binary()) => json_value()}

  @type t :: %{
          signed: %{
            protected_segment: binary(),
            payload_segment: binary(),
            signature_segment: binary(),
            protected_segment_digest: binary(),
            payload_segment_digest: binary(),
            receipt_digest: binary()
          },
          claims: %{required(binary()) => json_value()},
          provenance: %{
            charter_id: binary(),
            revision_digest: binary(),
            revision_number: pos_integer(),
            issuing_party_role: binary(),
            signing_key_id: binary(),
            signer_thumbprint: binary(),
            alg: binary(),
            revision_status: binary(),
            scope_status: binary()
          },
          grant: %{
            status: binary(),
            reason: binary() | nil,
            claimed_digest: binary() | nil,
            reference_digest: binary() | nil
          },
          agreement: %{
            status: binary(),
            reason: binary() | nil,
            fields: [binary()],
            governing_revision_digest: binary() | nil,
            governing_revision_number: pos_integer() | nil
          },
          not_verified: [binary()]
        }

  @doc false
  @spec build(
          binary(),
          Receipt.t(),
          ChainFacts.t(),
          %{required(binary()) => binary()},
          boolean(),
          :not_required | :matched | :outside | :not_verified,
          binary() | nil
        ) :: {:ok, t()} | {:error, Error.t()}
  def build(compact, receipt, chain, key, recognized?, scope, reference) do
    with {:ok, thumbprint} <- PartyDescriptor.signer_thumbprint(key),
         {:ok, governing} <- Chain.governing_revision(chain, receipt.occurred_at) do
      {:ok,
       %{
         signed: signed(compact, receipt),
         claims: JSON.decode!(receipt.envelope.payload_bytes),
         provenance: %{
           charter_id: receipt.charter_id,
           revision_digest: receipt.revision_digest,
           revision_number: receipt.revision_number,
           issuing_party_role: receipt.issuing_party_role,
           signing_key_id: receipt.envelope.kid,
           signer_thumbprint: thumbprint,
           alg: receipt.envelope.alg,
           revision_status: if(recognized?, do: "verified", else: "not_verified"),
           scope_status: Atom.to_string(scope)
         },
         grant: grant(receipt.grant.grant_digest, reference),
         agreement: agreement(governing, chain, receipt),
         not_verified: Enum.map(Facts.not_verified_floor(), &Atom.to_string/1)
       }}
    end
  end

  defp signed(compact, receipt) do
    [protected, payload, signature] = :binary.split(compact, ".", [:global])

    %{
      protected_segment: protected,
      payload_segment: payload,
      signature_segment: signature,
      protected_segment_digest: protected |> Digest.of() |> Digest.to_tagged(),
      payload_segment_digest: payload |> Digest.of() |> Digest.to_tagged(),
      receipt_digest: Receipt.digest(receipt)
    }
  end

  defp grant(claimed, reference) do
    {status, reason} =
      cond do
        claimed == nil -> {"not_verified", "receipt_grant_digest_missing"}
        reference == nil -> {"not_verified", "grant_reference_missing"}
        claimed == reference -> {"matches", nil}
        true -> {"differs", nil}
      end

    %{status: status, reason: reason, claimed_digest: claimed, reference_digest: reference}
  end

  defp agreement(governing, _chain, _receipt) when governing in [:none, :contested] do
    reason =
      if governing == :contested,
        do: "contested_governing_revision",
        else: "no_governing_revision"

    %{
      status: "not_verified",
      reason: reason,
      fields: [],
      governing_revision_digest: nil,
      governing_revision_number: nil
    }
  end

  defp agreement(governing, chain, receipt) do
    governing_facts = Enum.find(chain.revision_facts, &(&1.revision_digest == governing))
    revision = governing_facts.revision
    roles = MapSet.new(revision.parties, & &1.role)

    deployment_matches? =
      Enum.any?(revision.abp_bindings, fn binding ->
        binding.party_role == receipt.agent_party_role and
          binding.deployment_digest == receipt.deployment_digest
      end)

    comparisons = [
      agent_party_role: MapSet.member?(roles, receipt.agent_party_role),
      deployment_digest: deployment_matches?,
      issuing_party_role: MapSet.member?(roles, receipt.issuing_party_role),
      revision_digest: governing == receipt.revision_digest,
      revision_number: revision.revision_number == receipt.revision_number
    ]

    fields = for {field, false} <- comparisons, do: Atom.to_string(field)

    %{
      status: if(fields == [], do: "matches", else: "differs"),
      reason: nil,
      fields: fields,
      governing_revision_digest: governing,
      governing_revision_number: revision.revision_number
    }
  end
end
