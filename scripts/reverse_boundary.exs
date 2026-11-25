defmodule CharterAgreementProtocol.ReverseBoundary do
  @moduledoc false

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{Acceptance, ChainFacts, Error, Limits}

  # Host records cannot be encoded in the wire corpus. Run identical calls in
  # the package being compared, using the same verified inputs from the corpus.
  def outcomes(cases) do
    [left, right] = equivocation_pair(input(cases, "acceptance-same-signer-equivocation"))
    datetime = ~U[2026-09-01 00:00:00Z]
    descriptor = input(cases, "signing-ed25519-party_descriptor")
    signing = Map.take(descriptor, ["kid", "claims", "algorithm"])
    {:ok, frame} = CAP.descriptor_signing_input(signing)

    with_enumerable =
      put_in(signing, ["claims", "extensions", "optional", "com.example/opaque"], MapSet.new())

    fields = %{
      "api-equivocation-nil-digest" =>
        outcome(fn -> Acceptance.equivocation(left, %{right | acceptance_digest: nil}) end),
      "api-equivocation-missing-digest" =>
        outcome(fn -> Acceptance.equivocation(left, Map.delete(right, :acceptance_digest)) end),
      "api-governing-nil-zone-abbreviation" =>
        outcome(fn -> CAP.governing_revision(%ChainFacts{}, %{datetime | zone_abbr: nil}) end),
      "api-governing-missing-year" =>
        outcome(fn -> CAP.governing_revision(%ChainFacts{}, Map.delete(datetime, :year)) end),
      "api-governing-invalid-day" =>
        outcome(fn -> CAP.governing_revision(%ChainFacts{}, %{datetime | day: 99}) end),
      "api-assemble-missing-alg" =>
        outcome(fn -> CAP.assemble_compact(Map.delete(frame, :alg), <<0::512>>) end),
      "api-signing-claims-enumerable-struct" =>
        outcome(fn -> CAP.descriptor_signing_input(with_enumerable) end)
    }

    Map.merge(fields, retained_outcomes(cases))
  end

  defp input(cases, id), do: Enum.find(cases, &(&1["id"] == id))["input"]

  defp retained_outcomes(cases) do
    entry = input(cases, "signing-ed25519-acceptance")
    view = entry["context"]["set"]
    limits = Limits.default()
    {:ok, revision} = CAP.decode_charter_revision(hd(view["revisions"]), limits)
    {:ok, descriptor} = CAP.decode_party_descriptor(hd(view["descriptors"]), limits)

    {:ok, set} =
      CAP.build_set(
        view["revisions"],
        view["acceptances"],
        view["terminations"],
        view["descriptors"]
      )

    signing = Map.take(entry, ["kid", "claims", "algorithm"])

    %{
      "api-signing-set-missing-list" =>
        outcome(fn -> CAP.acceptance_signing_input(signing, Map.delete(set, :terminations)) end),
      "api-revision-digest-missing-bytes" =>
        outcome(fn -> CAP.revision_digest(Map.delete(revision, :canonical_bytes)) end),
      "api-descriptor-digest-missing-envelope" =>
        outcome(fn -> CAP.descriptor_digest(Map.delete(descriptor, :envelope)) end)
    }
  end

  defp equivocation_pair(input) do
    limits = Limits.default()
    {:ok, chain} = CAP.verify_descriptor_chain(input["descriptor_compacts"], limits)

    Enum.map(input["signed_revisions"], fn artifact ->
      {:ok, revision} = CAP.decode_charter_revision(artifact["revision_text"], limits)
      {:ok, facts} = CAP.verify_acceptance(artifact["compact"], revision, chain, limits)
      facts
    end)
  end

  defp outcome(function) do
    case function.() do
      {:ok, _value} -> "valid"
      digest when is_binary(digest) -> "valid"
      {:error, %Error{code: code}} -> Atom.to_string(code)
    end
  rescue
    _error -> "raised"
  end
end
