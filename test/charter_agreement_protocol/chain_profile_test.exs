defmodule CharterAgreementProtocol.ChainProfileTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{
    Capability.Profile,
    Chain,
    ChainFacts,
    ChainFixture,
    Error,
    Limits
  }

  setup do
    setup = ChainFixture.base()
    acceptances = ChainFixture.dual_acceptances(setup.genesis, setup)

    view = %{
      revisions: [setup.genesis.bytes],
      acceptances: Enum.map(acceptances, & &1.compact),
      descriptors: ChainFixture.descriptors(setup),
      terminations: []
    }

    %{view: view}
  end

  test "the full profile over verify/6 is exactly verify/5", %{view: view} do
    assert Chain.verify(
             view.revisions,
             view.acceptances,
             view.descriptors,
             view.terminations,
             Limits.default()
           ) ==
             Chain.verify(
               view.revisions,
               view.acceptances,
               view.descriptors,
               view.terminations,
               Limits.default(),
               Profile.full()
             )
  end

  test "an algorithm-excluding profile rejects the view with the named code before crypto",
       %{view: view} do
    {:ok, profile} = Profile.new(algorithms: ["Ed25519"])

    assert {:error, %Error{code: :algorithm_outside_profile}} =
             Chain.verify(
               view.revisions,
               view.acceptances,
               view.descriptors,
               view.terminations,
               Limits.default(),
               profile
             )
  end

  test "a revision-excluding profile rejects the view with the named code", %{view: view} do
    {:ok, profile} = Profile.new(revisions: {2, 3})

    assert {:error, %Error{code: :revision_outside_profile}} =
             Chain.verify(
               view.revisions,
               view.acceptances,
               view.descriptors,
               view.terminations,
               Limits.default(),
               profile
             )
  end

  test "an in-profile narrowing preserves the verified result", %{view: view} do
    {:ok, profile} = Profile.new(algorithms: ["EdDSA", "Ed25519"], revisions: {1, 3})

    assert {:ok, %ChainFacts{}} =
             Chain.verify(
               view.revisions,
               view.acceptances,
               view.descriptors,
               view.terminations,
               Limits.default(),
               profile
             )
  end

  test "a malformed profile fails closed before any input validation", %{view: view} do
    profile = %Profile{algorithms: ["Ed448"], revisions: {1, 3}}

    assert {:error, %Error{code: :invalid_profile}} =
             Chain.verify(
               view.revisions,
               view.acceptances,
               view.descriptors,
               view.terminations,
               Limits.default(),
               profile
             )

    # and it precedes even malformed input, like invalid_limits does
    assert {:error, %Error{code: :invalid_profile}} =
             Chain.verify(
               "not-a-list",
               view.acceptances,
               view.descriptors,
               [],
               Limits.default(),
               profile
             )
  end

  test "invalid limits still win over an invalid profile (existing precedence)", %{view: view} do
    profile = %Profile{algorithms: [], revisions: {1, 3}}
    bad_limits = %{Limits.default() | max_depth: -1}

    assert {:error, %Error{code: :invalid_limits}} =
             Chain.verify(
               view.revisions,
               view.acceptances,
               view.descriptors,
               view.terminations,
               bad_limits,
               profile
             )
  end
end
