defmodule CharterAgreementProtocol.SigningOracleTest do
  use ExUnit.Case, async: true
  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    Algorithm,
    Base64Url,
    Capability.Profile,
    Chain,
    CharterRevision,
    Error,
    Limits,
    PartyDescriptor,
    Signature,
    SigningInput
  }

  test "descriptor and receipt corpus inputs agree before the signature step" do
    for {file, kind} <- [
          {"party_descriptor-verify", :party_descriptor},
          {"receipt-verify", :receipt}
        ],
        one <- :json.decode(File.read!("priv/conformance/cases/#{file}.json"))["cases"] do
      source = one["input"]

      with [protected, payload, _signature] <- String.split(source["compact"], "."),
           {:ok, protected_bytes} <- Base64Url.decode(protected),
           {:ok, header} <- JSON.decode(protected_bytes),
           {:ok, bytes} <- Base64Url.decode(payload),
           {:ok, claims} <- JSON.decode(bytes) do
        {context, keys} = context_and_keys(kind, source, claims)

        alg =
          if claims["protocol_revision"] == 3 and Enum.any?(keys, &(elem(&1, 1) == "ML-DSA-65")),
            do: "ML-DSA-65",
            else: "Ed25519"

        claims = Map.put(claims, "protocol_revision", Algorithm.emissions()[alg])

        input = %{"kid" => header["kid"], "claims" => claims, "algorithm" => alg}
        profile = profile(source)

        case SigningInput.build(kind, input, Limits.default()) do
          {:error, %Error{code: :signing_input_invalid}} ->
            assert {:error, %Error{code: :signing_input_invalid}} =
                     CAP.prepare_signing(
                       kind,
                       snapshot(input, other_key(alg)),
                       context,
                       Limits.default(),
                       profile
                     )

          {:ok, signing_input, _artifact} ->
            %{signature_bytes: length} = Algorithm.row_for(alg)

            compact =
              signing_input.message <> "." <> Base64Url.encode(:binary.copy(<<0>>, length))

            result = verify(kind, compact, context, profile)

            eligible =
              Enum.filter(keys, fn {key, algorithm, kid} ->
                kid == input["kid"] and algorithm == alg and Signature.valid_key?(key, alg)
              end)

            for public <- Enum.map(eligible, &elem(&1, 0)) ++ [other_key(alg)] do
              prepared =
                CAP.prepare_signing(
                  kind,
                  snapshot(input, public),
                  context,
                  Limits.default(),
                  profile
                )

              case result do
                {:error, %Error{code: code}}
                when code not in [:signature_invalid, :descriptor_key_invalid] ->
                  assert {:error, %Error{code: ^code}} = prepared

                _signature_step ->
                  if kind == :receipt and is_struct(context, CharterRevision) do
                    assert {:ok, %{key: :unnamed}} = prepared
                  else
                    if Enum.any?(eligible, &(elem(&1, 0) == public)),
                      do: assert(match?({:ok, %{key: :matched}}, prepared)),
                      else:
                        assert(match?({:error, %Error{code: :signing_key_mismatch}}, prepared))
                  end
              end
            end
        end
      end
    end
  end

  defp snapshot(input, public), do: Map.put(input, "public_key", public)

  defp context_and_keys(:party_descriptor, input, _claims) do
    context =
      Enum.reduce(input["predecessor_compacts"] || [], nil, fn compact, previous ->
        {:ok, facts} = PartyDescriptor.verify(compact, previous, Limits.default())
        facts
      end)

    keys =
      if context do
        Enum.filter(context.descriptor.verification_keys, &(&1.status == :active))
        |> Enum.map(&{&1.public_key, &1.algorithm, &1.key_id})
      else
        [_, payload, _] = String.split(input["compact"], ".")
        {:ok, bytes} = Base64Url.decode(payload)
        raw = JSON.decode!(bytes)

        for key <- raw["verification_keys"] || [],
            key["status"] == "active",
            {:ok, public} <- [Base64Url.decode(key["public_key"])],
            do: {public, key["algorithm"], key["key_id"]}
      end

    {context, keys}
  end

  defp context_and_keys(:receipt, %{"revision_text" => text}, _claims) do
    {:ok, revision} = CharterRevision.decode(text, Limits.default())
    {revision, []}
  end

  defp context_and_keys(:receipt, %{"chain" => set}, claims) do
    {:ok, chain} =
      Chain.verify(
        set["revisions"],
        set["acceptances"],
        set["descriptors"],
        set["terminations"],
        Limits.default()
      )

    accepted = Enum.filter(chain.revision_facts, &(&1.acceptance_status == :accepted))
    recognized = Enum.any?(accepted, &(&1.revision_digest == claims["revision_digest"]))

    digests =
      accepted
      |> Enum.filter(&(not recognized or &1.revision_digest == claims["revision_digest"]))
      |> Enum.flat_map(& &1.revision.parties)
      |> Enum.filter(&(&1.role == claims["issuing_party_role"]))
      |> Enum.map(& &1.party_descriptor_digest)

    keys =
      chain.descriptor_chains
      |> Enum.flat_map(& &1.descriptors)
      |> Enum.filter(&(&1.descriptor_digest in digests))
      |> Enum.flat_map(& &1.descriptor.verification_keys)
      |> Enum.filter(&(&1.status == :active))
      |> Enum.map(&{&1.public_key, &1.algorithm, &1.key_id})

    {chain, keys}
  end

  defp profile(input) do
    selected = input["profile"] || %{}
    range = selected["revisions"]

    {:ok, profile} =
      Profile.new(
        algorithms: selected["algorithms"],
        revisions: if(range, do: {range["min"], range["max"]}, else: nil)
      )

    profile
  end

  defp other_key("Ed25519"),
    do: elem(:crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<9>>, 32)), 0)

  defp other_key("ML-DSA-65"), do: <<0::1952*8>>

  defp verify(:party_descriptor, compact, context, profile),
    do: CAP.verify_descriptor(compact, context, Limits.default(), profile)

  defp verify(:receipt, compact, context, profile),
    do: CAP.verify_receipt(compact, context, Limits.default(), profile)
end
