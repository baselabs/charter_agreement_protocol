defmodule CharterAgreementProtocol.ReleaseIdentityTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Algorithm, ReleaseIdentity}

  test "the manifest schema version is a positive integer" do
    assert is_integer(ReleaseIdentity.manifest_version()) and
             ReleaseIdentity.manifest_version() >= 1
  end

  test "the semantics identity is at least the latest family in the mapping" do
    latest = List.last(ReleaseIdentity.verification_semantics_history())
    assert ReleaseIdentity.verification_semantics() >= latest.verification_semantics
  end

  test "every family row carries package versions, census, revisions, and transitions" do
    for row <- ReleaseIdentity.compatibility() do
      assert is_list(row.package_versions) and row.package_versions != []
      assert is_binary(row.census_digest)
      assert is_list(row.protocol_revisions) and row.protocol_revisions != []

      for transition <- row.transitions do
        assert transition.class in [:admission, :verdict_narrowing, :resource_boundary, :typed_error]
        assert transition.direction in [:green_to_red, :red_to_green, :crash_to_typed]
        assert is_binary(transition.description) and byte_size(transition.description) > 0
      end
    end
  end

  test "the retroactive mapping covers every released package exactly once, in order" do
    history = ReleaseIdentity.verification_semantics_history()
    all_versions = history |> Enum.flat_map(& &1.package_versions) |> Enum.sort()
    assert all_versions == Enum.uniq(all_versions)

    # monotone semantics across the ordered families
    semantics = Enum.map(history, & &1.verification_semantics)
    assert semantics == Enum.sort(semantics)
    assert semantics == Enum.uniq(semantics)
  end

  test "revision coverage grows monotonically and stays within the registry" do
    accepted = Algorithm.accepted_protocol_revisions()
    history = ReleaseIdentity.verification_semantics_history()
    coverage = Enum.map(history, & &1.protocol_revisions)

    assert coverage == Enum.map(coverage, &Enum.sort/1)
    for revisions <- coverage, do: assert(Enum.all?(revisions, &(&1 in accepted)))
  end

  test "the latest family row exists and carries exactly the descriptor timestamp transition" do
    [s4 | _] = Enum.reverse(ReleaseIdentity.compatibility())
    assert s4.verification_semantics == 4
    assert [%{class: :verdict_narrowing, direction: :green_to_red}] = s4.transitions
  end
end
