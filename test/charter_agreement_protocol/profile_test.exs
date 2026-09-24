defmodule CharterAgreementProtocol.ProfileTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Algorithm, Capability.Profile, Error}

  test "the full profile admits every registry pair" do
    full = Profile.full()

    for row <- Algorithm.registry(),
        revision <- Algorithm.accepted_protocol_revisions() do
      assert Profile.admits?(full, row.name, revision)
    end
  end

  test "new defaults to the full profile" do
    assert {:ok, profile} = Profile.new([])
    assert profile == Profile.full()
  end

  test "new narrows the algorithm axis to registry names" do
    assert {:ok, %Profile{algorithms: ["Ed25519"]}} = Profile.new(algorithms: ["Ed25519"])
  end

  test "new narrows the revision axis inside the accepted set" do
    assert {:ok, %Profile{revisions: {1, 2}}} = Profile.new(revisions: {1, 2})
  end

  test "new rejects unknown names, duplicates, and non-lists" do
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(algorithms: ["Ed448"])
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(algorithms: [])
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(algorithms: ["Ed25519", "Ed25519"])
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(algorithms: "Ed25519")
  end

  test "new rejects revision bounds outside the accepted set or inverted" do
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(revisions: {0, 2})
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(revisions: {2, 1})
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(revisions: {1, 4})
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(revisions: {1})
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(revisions: "1..2")
  end

  test "new rejects unknown options and non-keyword input" do
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(algs: ["Ed25519"])
    assert {:error, %Error{code: :invalid_profile}} = Profile.new("profile")
  end

  test "valid? accepts constructed profiles and rejects everything else" do
    assert Profile.valid?(Profile.full())
    assert {:ok, narrow} = Profile.new(algorithms: ["Ed25519"], revisions: {1, 2})
    assert Profile.valid?(narrow)
    refute Profile.valid?(%Profile{algorithms: ["Ed448"], revisions: {1, 3}})
    refute Profile.valid?(%Profile{algorithms: [], revisions: {1, 3}})
    refute Profile.valid?(%Profile{algorithms: ["Ed25519"], revisions: {2, 1}})
    refute Profile.valid?(struct!(Profile, algorithms: nil, revisions: nil))
    refute Profile.valid?("profile")
    refute Profile.valid?(nil)
  end

  test "admits? is per artifact and axis-exact" do
    {:ok, profile} = Profile.new(algorithms: ["Ed25519"], revisions: {1, 2})

    assert Profile.admits?(profile, "Ed25519", 1)
    assert Profile.admits?(profile, "Ed25519", 2)
    # out on the algorithm axis only
    refute Profile.admits?(profile, "EdDSA", 1)
    refute Profile.admits?(profile, "ML-DSA-65", 1)
    # out on the revision axis only
    refute Profile.admits?(profile, "Ed25519", 3)
    refute Profile.admits?(profile, "Ed25519", 0)
    refute Profile.admits?(profile, "Ed25519", nil)
    refute Profile.admits?(profile, nil, 1)
  end

  test "the profile error codes are declared" do
    assert Error.declared?(:invalid_profile)
    assert Error.declared?(:algorithm_outside_profile)
    assert Error.declared?(:revision_outside_profile)
  end
end
