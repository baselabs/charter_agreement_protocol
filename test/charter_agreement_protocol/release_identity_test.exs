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
        assert transition.class in [
                 :admission,
                 :verdict_narrowing,
                 :resource_boundary,
                 :typed_error,
                 :error_code_change
               ]

        assert transition.direction in [
                 :green_to_red,
                 :red_to_green,
                 :crash_to_typed,
                 :red_to_red
               ]

        assert is_binary(transition.description) and byte_size(transition.description) > 0
      end
    end
  end

  test "the retroactive mapping covers every released package exactly once, in order" do
    history = ReleaseIdentity.verification_semantics_history()
    all_versions = history |> Enum.flat_map(& &1.package_versions) |> Enum.sort()
    assert all_versions == Enum.uniq(all_versions)

    # semantics never decreases across the ordered rows; a family may span
    # several rows (one per certified census), and only a family's first row
    # carries transitions: a later row in the same family changed no verdict
    semantics = Enum.map(history, & &1.verification_semantics)
    assert semantics == Enum.sort(semantics)

    Enum.zip(history, tl(history))
    |> Enum.filter(fn {prior, later} ->
      prior.verification_semantics == later.verification_semantics
    end)
    |> Enum.each(fn {prior, later} ->
      assert later.transitions == []
      assert later.census_digest != prior.census_digest
    end)
  end

  test "revision coverage grows monotonically and stays within the registry" do
    accepted = Algorithm.accepted_protocol_revisions()
    history = ReleaseIdentity.verification_semantics_history()
    coverage = Enum.map(history, &MapSet.new(&1.protocol_revisions))

    for revisions <- coverage, do: assert(Enum.all?(revisions, &(&1 in accepted)))

    # each family's coverage is a superset of the prior family's
    Enum.zip(coverage, tl(Enum.to_list(coverage)))
    |> Enum.each(fn {prior, later} -> assert MapSet.subset?(prior, later) end)
  end

  test "the latest corpus row records malformed context transitions" do
    [latest | _] = Enum.reverse(ReleaseIdentity.compatibility())
    assert latest.verification_semantics == ReleaseIdentity.verification_semantics()
    assert latest.package_versions == ["0.6.0"]
    assert Enum.any?(latest.transitions, &(&1.direction == :green_to_red))
    assert Enum.any?(latest.transitions, &(&1.direction == :crash_to_typed))
  end
end
