defmodule CharterAgreementProtocol.OptionValidationPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CharterAgreementProtocol, as: CAP
  alias CharterAgreementProtocol.{Capability.Profile, Error, Limits}

  test "a limits struct tag without fields returns false" do
    refute Limits.valid?(%{__struct__: Limits})
  end

  test "limits with max_bytes removed return false" do
    refute Limits.valid?(Map.delete(Limits.default(), :max_bytes))
  end

  test "an improper profile algorithm list returns false" do
    refute Profile.valid?(%Profile{algorithms: ["Ed25519" | :tail], revisions: {1, 3}})
    assert {:error, %Error{code: :invalid_profile}} = Profile.new(algorithms: ["Ed25519" | :tail])
  end

  property "malformed limits structs maps and improper lists return invalid_limits" do
    missing =
      list_of(member_of(Limits.fields()), min_length: 1) |> map(&Map.drop(Limits.default(), &1))

    bad_field =
      tuple({member_of(Limits.fields()), one_of([constant(nil), binary(), constant(-1)])})
      |> map(fn {field, value} -> Map.put(Limits.default(), field, value) end)

    malformed =
      one_of([
        missing,
        bad_field,
        constant(%{__struct__: Limits}),
        map_of(atom(:alphanumeric), integer()),
        improper_lists()
      ])

    check all(limits <- malformed, max_runs: 200) do
      refute Limits.valid?(limits)
      assert {:error, %Error{code: :invalid_limits}} = Limits.check(limits)

      assert_invalid(
        CAP.prepare_signing(:party_descriptor, %{}, nil, limits, Profile.full()),
        :invalid_limits
      )

      if is_struct(limits, Limits) do
        for result <- surfaces(limits, Profile.full()),
            do: assert_invalid(result, :invalid_limits)

        for result <- limits_surfaces(limits), do: assert_invalid(result, :invalid_limits)
      end
    end
  end

  property "malformed profile structs maps and improper algorithms return invalid_profile" do
    algorithms = improper_lists() |> map(&%Profile{algorithms: &1, revisions: {1, 3}})
    missing = member_of([:algorithms, :revisions]) |> map(&Map.delete(Profile.full(), &1))

    malformed =
      one_of([
        algorithms,
        missing,
        constant(%{__struct__: Profile}),
        map_of(atom(:alphanumeric), integer()),
        improper_lists()
      ])

    check all(profile <- malformed, max_runs: 200) do
      refute Profile.valid?(profile)
      assert {:error, %Error{code: :invalid_profile}} = Profile.check(profile)

      assert_invalid(
        CAP.prepare_signing(:party_descriptor, %{}, nil, Limits.default(), profile),
        :invalid_profile
      )

      if is_struct(profile, Profile) do
        for result <- surfaces(Limits.default(), profile),
            do: assert_invalid(result, :invalid_profile)
      end
    end
  end

  property "constructing profiles with improper algorithms returns invalid_profile" do
    check all(algorithms <- improper_lists(), max_runs: 100) do
      assert {:error, %Error{code: :invalid_profile}} = Profile.new(algorithms: algorithms)
    end
  end

  defp improper_lists do
    tuple(
      {list_of(member_of(["Ed25519", "EdDSA"]), min_length: 1),
       one_of([integer(), binary(), constant(nil), constant(%{})])}
    )
    |> map(fn {prefix, tail} -> Enum.reduce(Enum.reverse(prefix), tail, &[&1 | &2]) end)
  end

  defp surfaces(limits, profile) do
    [
      CAP.prepare_signing(:party_descriptor, %{}, nil, limits, profile),
      CAP.verify_descriptor("", nil, limits, profile),
      CAP.verify_descriptor_chain([""], limits, profile),
      CAP.verify_acceptance("", nil, nil, limits, profile),
      CAP.verify_termination("", nil, nil, limits, profile),
      CAP.verify_receipt("", nil, limits, profile),
      CAP.verify_chain([], [], [], [], limits, profile)
    ]
  end

  defp limits_surfaces(limits) do
    [
      CAP.decode_party_descriptor("", limits),
      CAP.decode_charter_revision("", limits),
      CAP.verify_descriptor("", nil, limits),
      CAP.verify_descriptor_chain([], limits),
      CAP.verify_acceptance("", nil, nil, limits),
      CAP.verify_termination("", nil, nil, limits),
      CAP.verify_receipt("", nil, limits),
      CAP.verify_chain([], [], [], [], limits)
    ]
  end

  defp assert_invalid(result, code), do: assert({:error, %Error{code: ^code}} = result)
end
