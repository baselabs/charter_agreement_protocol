defmodule CharterAgreementProtocol.EffectiveFromFloorTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{DescriptorFixture, Limits, PartyDescriptor}

  test "a long-fraction effective_from rejects at the schema stage like every sibling timestamp" do
    # 60 fractional digits: 76 bytes total — a codec-valid RFC 3339 spelling
    # whose sibling timestamp members have rejected since the resource
    # boundary act. The descriptor floor now matches (S4 transition).
    long_fraction = "2026-08-25T10:00:00." <> String.duplicate("1", 60) <> "Z"
    descriptor = DescriptorFixture.genesis(claims: %{"effective_from" => long_fraction})

    assert {:error, %{code: :constraint_violation}} =
             PartyDescriptor.decode(descriptor.compact, Limits.default())
  end

  test "an ordinary effective_from still verifies" do
    descriptor = DescriptorFixture.genesis()
    assert {:ok, _} = PartyDescriptor.verify(descriptor.compact, nil, Limits.default())
  end
end
