defmodule CharterAgreementProtocol.CapabilityLaneTest do
  @moduledoc false
  # The capability-limited lane's assertions, written substrate-neutrally so
  # the SAME test is green on a capable substrate and on a limited one
  # (Ubuntu 24.04 / OpenSSL 3.0.13): the probe's verdicts must agree with
  # actual verification behavior, and verification under a declared
  # capability obstacle fails with the honest named diagnostic, never a
  # forgery verdict.
  use ExUnit.Case, async: false

  alias CharterAgreementProtocol.{
    Capability,
    Capability.Profile,
    Chain,
    ChainFixture,
    DescriptorFacts,
    Error,
    Limits,
    PartyDescriptor,
    Signature
  }

  test "the report's per-row verdicts agree with actual verification behavior" do
    for %{key_algorithm: key_algorithm, verifiable: verifiable?} <- Capability.report().algorithms do
      assert verifiable? == Capability.kat_verifies?(key_algorithm)
    end
  end

  test "ed25519 artifacts verify green on every substrate this suite runs on" do
    assert Capability.kat_verifies?("Ed25519")

    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519, :binary.copy(<<7>>, 32))
    message = "lane"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    assert :ok = Signature.verify(message, signature, public_key, "EdDSA")
  end

  test "ml-dsa verification honors the substrate honestly: green where capable, the named diagnostic where not" do
    if Capability.declared?("ML-DSA-65") do
      {public_key, private_key} = :crypto.generate_key(:mldsa65, [])
      message = "lane"
      signature = :crypto.sign(:mldsa65, :none, message, {:expandedkey, private_key})
      assert :ok = Signature.verify(message, signature, public_key, "ML-DSA-65")
    else
      # Key generation itself is impossible on this substrate; the honest
      # failure is reachable with right-length bytes because the substrate
      # gate fires after the deterministic length checks, before crypto.
      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} =
               Signature.verify("lane", <<0::3309*8>>, <<0::1952*8>>, "ML-DSA-65")
    end
  end

  test "a real unsupported crypto operation is rescued by the live known-answer probe" do
    if not Capability.declared?("ML-DSA-65") do
      assert_raise ErlangError, fn ->
        :crypto.verify(:mldsa65, :none, "lane", <<0::3309*8>>, <<0::1952*8>>)
      end

      refute Capability.kat_verifies?("ML-DSA-65", true)
    end
  end

  test "a raising signature operation runs a fresh known-answer verification" do
    if not Capability.declared?("ML-DSA-65") do
      {result, calls} =
        CharterAgreementProtocol.CryptoTrace.count(:verify, fn ->
          Signature.substrate_outcome("ML-DSA-65", true, fn ->
            :crypto.verify(:mldsa65, :none, "lane", <<0::3309*8>>, <<0::1952*8>>)
          end)
        end)

      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} = result
      assert length(calls) == 2
    end
  end

  test "a predecessor the runtime cannot check reports the substrate diagnostic, never a broken chain" do
    corpus = :json.decode(File.read!("priv/conformance/cases/party_descriptor-verify.json"))
    compact_of = fn id -> Enum.find(corpus["cases"], &(&1["id"] == id))["input"]["compact"] end
    mldsa_genesis = compact_of.("descriptor-mldsa65-rev3-valid")
    {:ok, decoded} = PartyDescriptor.decode(mldsa_genesis, Limits.default())
    digest = PartyDescriptor.digest(decoded)

    # The supplied facts only name the history; verification re-verifies it.
    predecessor = %DescriptorFacts{
      descriptor: decoded,
      descriptor_digest: digest,
      party_id: digest,
      descriptor_number: 1,
      prev_descriptor_digest: nil,
      signing_key_id: decoded.envelope.kid,
      descriptor_position: :head,
      optional_extensions_retained: [],
      lineage: [mldsa_genesis],
      not_verified: []
    }

    # The target is an unrelated genesis, so once the predecessor history
    # verifies the call fails as a broken chain.
    target = compact_of.("party-descriptor-genesis-valid")
    result = PartyDescriptor.verify(target, predecessor, Limits.default())

    if Capability.declared?("ML-DSA-65") do
      assert {:error, %Error{code: :descriptor_chain_invalid}} = result
    else
      assert {:error, %Error{code: :algorithm_unsupported_on_substrate}} = result
    end
  end

  test "an ed25519-profiled view verifies identically on every substrate" do
    setup = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)

    {:ok, profile} = Profile.new(algorithms: ["EdDSA"], revisions: {1, 1})

    assert {:ok, _facts} =
             Chain.verify(
               [setup.genesis.bytes],
               Enum.map(acceptances, & &1.compact),
               ChainFixture.descriptors(setup),
               [],
               Limits.default(),
               profile
             )
  end

  test "preparation checks runtime support for every kind and bare revision receipts" do
    %{"cases" => cases} = :json.decode(File.read!("priv/conformance/cases/signing-prepare.json"))

    for kind <- [:party_descriptor, :acceptance, :termination, :receipt] do
      id = "signing-mldsa65-#{kind}"
      input = Enum.find(cases, &(&1["id"] == id))["input"]

      value =
        Map.take(input, ["kid", "claims", "algorithm"])
        |> Map.put("public_key", Base.url_decode64!(input["public_key"], padding: false))

      context =
        case input["context"] do
          :null ->
            nil

          %{"set" => set} ->
            struct(CharterAgreementProtocol.ArtifactSet,
              revisions: set["revisions"],
              acceptances: set["acceptances"],
              descriptors: set["descriptors"],
              terminations: set["terminations"]
            )

          %{"chain" => set} ->
            retained_chain(set)
        end

      result =
        CharterAgreementProtocol.prepare_signing(
          kind,
          value,
          context,
          Limits.default(),
          Profile.full()
        )

      if Capability.declared?("ML-DSA-65"),
        do: assert(match?({:ok, _}, result)),
        else: assert(match?({:error, %Error{code: :algorithm_unsupported_on_substrate}}, result))

      assert {:error, %Error{code: :signing_key_invalid}} =
               CharterAgreementProtocol.prepare_signing(
                 kind,
                 Map.put(value, "public_key", <<>>),
                 context,
                 Limits.default(),
                 Profile.full()
               )

      if kind == :receipt do
        set = input["context"]["chain"]

        {:ok, revision} =
          CharterAgreementProtocol.CharterRevision.decode(hd(set["revisions"]), Limits.default())

        result =
          CharterAgreementProtocol.prepare_signing(
            :receipt,
            value,
            revision,
            Limits.default(),
            Profile.full()
          )

        if Capability.declared?("ML-DSA-65"),
          do: assert(match?({:ok, _}, result)),
          else:
            assert(match?({:error, %Error{code: :algorithm_unsupported_on_substrate}}, result))
      end
    end
  end

  test "runtime results are retained per key algorithm" do
    for algorithm <- ["Ed25519", "ML-DSA-44", "ML-DSA-65", "ML-DSA-87"] do
      result = Capability.kat_verifies?(algorithm)
      assert :persistent_term.get({Capability, algorithm}).verifiable == result

      assert :persistent_term.get({Capability, algorithm}).declared ==
               Capability.declared?(algorithm)

      assert Capability.kat_verifies?(algorithm) == result
    end
  end

  defp retained_chain(set) do
    if Capability.declared?("ML-DSA-65") do
      {:ok, chain} =
        Chain.verify(
          set["revisions"],
          set["acceptances"],
          set["descriptors"],
          [],
          Limits.default()
        )

      chain
    else
      retained_bytes(set)
    end
  end

  defp retained_bytes(set) do
    # Retain the real corpus bytes without requiring this lane to verify them.
    revisions =
      Enum.map(set["revisions"], fn text ->
        {:ok, revision} = CharterAgreementProtocol.CharterRevision.decode(text, Limits.default())
        struct(CharterAgreementProtocol.RevisionFacts, revision: revision)
      end)

    acceptances =
      Enum.map(set["acceptances"], fn compact ->
        {:ok, acceptance} =
          CharterAgreementProtocol.Acceptance.decode_for_signing(compact, Limits.default())

        struct(CharterAgreementProtocol.AcceptanceFacts, acceptance: acceptance)
      end)

    descriptors =
      Enum.map(set["descriptors"], fn compact -> struct(DescriptorFacts, lineage: [compact]) end)

    struct(CharterAgreementProtocol.ChainFacts,
      revision_facts: revisions,
      acceptance_facts: acceptances,
      descriptor_chains: [
        struct(CharterAgreementProtocol.DescriptorChain, descriptors: descriptors)
      ],
      termination_facts: []
    )
  end
end

defmodule CharterAgreementProtocol.CapabilityLaneProbe do
  @moduledoc false
  # Informational lane output: the runtime's capability report, printed so a
  # lane log carries the substrate's declared verdicts alongside the
  # assertions above.
  use ExUnit.Case, async: true

  test "lane information: capability report" do
    report = CharterAgreementProtocol.capabilities()

    lines =
      for row <- report.algorithms do
        "#{row.name} (#{row.key_algorithm}): #{if row.verifiable, do: "verifiable", else: "NOT verifiable"}"
      end

    IO.puts(["capability lane report" | lines] |> Enum.join("\n"))
    assert is_list(report.algorithms)
  end
end
