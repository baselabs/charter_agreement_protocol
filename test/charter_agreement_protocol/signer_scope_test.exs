defmodule CharterAgreementProtocol.SignerScopeTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    AcceptanceFixture,
    ArtifactSet,
    Base64Url,
    Capability,
    Capability.Profile,
    CharterRevisionFixture,
    Error,
    Limits,
    SigningFixture,
    Timestamp
  }

  for {suffix, algorithm} <- [{"ed25519", "Ed25519"}, {"mldsa65", "ML-DSA-65"}] do
    @tag skip:
           algorithm == "ML-DSA-65" and not Capability.declared?(algorithm) and
             "runtime does not declare ML-DSA-65"
    test "scope restricts vote credit while retaining signatures with #{algorithm}" do
      suffix = unquote(suffix)
      input = input("chain-verify", "chain-outside", suffix)
      assert {:ok, view} = verify_chain(input)
      assert view.accepted_revision_digests == []
      assert [%{signature_status: :accepted, acceptance_status: :proposed}] = view.revision_facts

      assert %{
               scope_status: :outside,
               credit: :uncredited,
               credit_reason: :signer_outside_scope
             } = issuer_vote(view)

      outside = input("governing_revision", "governing-outside", suffix)
      assert {:ok, accepted} = verify_chain(outside)
      assert [%{scope_status: :outside, signer_thumbprint: thumbprint}] =
               accepted.termination_facts
      assert is_binary(thumbprint)
      assert [governing] = accepted.accepted_revision_digests
      [%{"at" => at}] = outside["queries"]
      assert {:ok, time} = Timestamp.parse(at)
      assert {:ok, ^governing} = CAP.governing_revision(accepted, time)

      inside = input("governing_revision", "governing-matched", suffix)
      assert {:ok, closed} = verify_chain(inside)
      assert {:ok, :none} = CAP.governing_revision(closed, time)
    end

    @tag skip:
           algorithm == "ML-DSA-65" and not Capability.declared?(algorithm) and
             "runtime does not declare ML-DSA-65"
    test "receipts report unverified scope without a named accepted revision with #{algorithm}" do
      suffix = unquote(suffix)
      limits = Limits.default()

      for {label, status} <- [{"receipt-matched", :matched}, {"receipt-outside", :outside}] do
        input = input("receipt-verify", label, suffix)
        assert {:ok, chain} = verify_chain(input["chain"])
        assert {:ok, facts} = CAP.verify_receipt(input["compact"], chain, limits)
        assert facts.scope_status == status
        assert "sha-256:" <> _thumbprint = facts.signer_thumbprint
      end

      bare = input("receipt-verify", "receipt-unverified-bare-revision", suffix)
      assert {:ok, revision} = CAP.decode_charter_revision(bare["revision_text"], limits)

      assert {:ok, %{scope_status: :not_verified, signer_thumbprint: nil}} =
               CAP.verify_receipt(bare["compact"], revision, limits)

      unknown = input("receipt-verify", "receipt-unverified-unrecognized-revision", suffix)
      assert {:ok, chain} = verify_chain(unknown["chain"])

      assert {:ok, %{scope_status: :not_verified, signer_thumbprint: nil}} =
               CAP.verify_receipt(unknown["compact"], chain, limits)
    end

    @tag skip:
           algorithm == "ML-DSA-65" and not Capability.declared?(algorithm) and
             "runtime does not declare ML-DSA-65"
    test "role credit precedes scope and scope still gates assignment with #{algorithm}" do
      algorithm = unquote(algorithm)
      issuer = descriptor(algorithm, "issuer")
      acceptor = descriptor(algorithm, "acceptor")
      assignee = descriptor(algorithm, "issuer")
      relay = signer(algorithm, "relay")
      observer = descriptor(algorithm, "observer", [relay])

      for {participation, reason} <-
            [{"arbiter", :arbiter_not_counted}, {"acceptor", :role_outside_quorum}] do
        genesis = revision(issuer, acceptor, observer, participation)
        marked = %{"replacement_role" => "issuer"}

        assignment = %{
          "role" => "issuer",
          "assignor_party_id" => issuer.digest,
          "assignor_descriptor_digest" => issuer.digest,
          "assignee_descriptor_digest" => assignee.digest,
          "assent_quorum" => %{"roles" => ["acceptor"], "threshold" => 1}
        }

        changes =
          genesis.claims
          |> Map.take(~w(protocol_revision parties acceptance_quorum termination_rules))
          |> Map.update!("parties", fn parties ->
            Enum.map(parties, fn
              %{"role" => "issuer"} = party ->
                %{party | "party_descriptor_digest" => assignee.digest}

              party ->
                party
            end)
          end)
          |> Map.put("party_replacements", [assignment])

        next = CharterRevisionFixture.successor(genesis, 2, claims: changes)
        descriptors = Enum.map([issuer, acceptor, assignee, observer], & &1.compact)

        votes = [
          vote(genesis, issuer, "issuer"),
          vote(genesis, acceptor, "acceptor"),
          vote(next, issuer, "issuer", marked),
          vote(next, assignee, "issuer"),
          vote(next, acceptor, "acceptor")
        ]

        for {signer, status, assignment_status} <-
              [{observer, :matched, :accepted}, {relay, :outside, :pending}] do
          claims = acceptance_claims(next, observer, "observer", %{})
          assent = SigningFixture.compact(:acceptance, claims, signer)
          limits = Limits.default()

          assert {:ok, view} =
                   CAP.verify_chain(
                     [genesis.bytes, next.bytes],
                     votes ++ [assent],
                     descriptors,
                     [],
                     limits
                   )

          facts = Enum.find(view.acceptance_facts, &(&1.party_role == "observer"))
          assert facts.scope_status == status
          assert facts.credit == :uncredited
          assert facts.credit_reason == reason
          assert [_genesis, successor] = view.revision_facts
          assert successor.assignment_status == assignment_status
          assert successor.signature_status == :accepted

          input = %{
            "claims" => claims,
            "kid" => signer.kid,
            "algorithm" => algorithm,
            "public_key" => signer.public
          }

          assert {:ok, set} =
                   ArtifactSet.build([genesis.bytes, next.bytes], votes, [], descriptors)

          prepared = CAP.prepare_signing(:acceptance, input, set, limits, Profile.full())

          if status == :matched do
            assert {:ok, plan} = prepared
            signature = SigningFixture.sign(plan.signing_input.message, signer)
            assert {:ok, _compact} = CAP.finish_signing(plan, signature)
          else
            assert {:error, %Error{code: :signing_refused, subject: ["signing_input", "scope"]}} =
                     prepared
          end
        end
      end
    end
  end

  defp verify_chain(input) do
    CAP.verify_chain(
      input["revisions"],
      input["acceptances"],
      input["descriptors"],
      input["terminations"],
      Limits.default()
    )
  end

  defp issuer_vote(view), do: Enum.find(view.acceptance_facts, &(&1.party_role == "issuer"))

  defp input(file, name, suffix) do
    path = Application.app_dir(:charter_agreement_protocol, "priv/conformance/cases/#{file}.json")
    %{"cases" => cases} = path |> File.read!() |> :json.decode()
    id = "signer-scope-#{name}-#{suffix}"
    Enum.find(cases, &(&1["id"] == id)) |> Map.fetch!("input")
  end

  defp signer("Ed25519" = algorithm, kid) do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    %{algorithm: algorithm, kid: kid, public: public, private: private}
  end

  defp signer("ML-DSA-65" = algorithm, kid) do
    {public, private} = :crypto.generate_key(:mldsa65, [])
    %{algorithm: algorithm, kid: kid, public: public, private: private}
  end

  defp descriptor(algorithm, role, additional \\ []) do
    signer = signer(algorithm, role)
    keys = Enum.map([signer | additional], &declaration/1)
    assert {:ok, thumbprint} = CAP.signer_thumbprint(hd(keys))

    claims = %{
      "protocol_revision" => 8,
      "descriptor_number" => 1,
      "verification_keys" => keys,
      "attestation_hints" => [],
      "extensions" => %{"critical" => %{}, "optional" => %{}},
      "effective_from" => "2026-08-25T10:00:00Z",
      "signing_scopes" => [
        %{
          "role" => role,
          "signers" => [%{"key_thumbprint" => thumbprint, "artifact_kinds" => ["acceptance"]}]
        }
      ]
    }

    digest =
      CharterRevisionFixture.tagged(:party_descriptor_content, SigningFixture.canonical(claims))

    Map.merge(signer, %{
      digest: digest,
      compact: SigningFixture.compact(:party_descriptor, claims, signer)
    })
  end

  defp declaration(signer) do
    %{
      "algorithm" => signer.algorithm,
      "key_id" => signer.kid,
      "public_key" => Base64Url.encode(signer.public),
      "status" => "active"
    }
  end

  defp revision(issuer, acceptor, observer, participation) do
    roles = ["acceptor", "issuer"]

    parties = [
      %{
        "role" => "acceptor",
        "participation" => "acceptor",
        "party_descriptor_digest" => acceptor.digest
      },
      %{
        "role" => "issuer",
        "participation" => "acceptor",
        "party_descriptor_digest" => issuer.digest
      },
      %{
        "role" => "observer",
        "participation" => participation,
        "party_descriptor_digest" => observer.digest
      }
    ]

    CharterRevisionFixture.genesis(
      claims: %{
        "protocol_revision" => 8,
        "parties" => parties,
        "acceptance_quorum" => %{"roles" => roles, "threshold" => 2},
        "termination_rules" => %{
          "reason_codes" => ["mutual"],
          "quorum" => %{"roles" => roles, "threshold" => 1}
        }
      }
    )
  end

  defp vote(revision, signer, role, overrides \\ %{}) do
    claims = acceptance_claims(revision, signer, role, overrides)
    SigningFixture.compact(:acceptance, claims, signer)
  end

  defp acceptance_claims(revision, signer, role, overrides) do
    AcceptanceFixture.claims(revision, signer, role, Map.put(overrides, "protocol_revision", 8))
  end
end
