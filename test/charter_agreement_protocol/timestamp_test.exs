defmodule CharterAgreementProtocol.TimestampTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Timestamp}

  test "accepts exact UTC RFC 3339 instants including fractions and valid leap-second positions" do
    assert {:ok, first} = Timestamp.parse("2024-02-29T23:59:59Z")
    assert {:ok, later} = Timestamp.parse("2024-02-29T23:59:59.000000001Z")
    assert Timestamp.compare(first, later) == :lt
    assert Timestamp.compare(later, first) == :gt

    assert {:ok, next_second} = Timestamp.parse("2024-03-01T00:00:00Z")
    assert Timestamp.compare(next_second, first) == :gt

    assert {:ok, leap} = Timestamp.parse("2016-12-31T23:59:60Z")
    assert {:ok, leap_fraction} = Timestamp.parse("2016-12-31T23:59:60.5Z")
    assert {:ok, before_leap} = Timestamp.parse("2016-12-31T23:59:59.999Z")
    assert {:ok, after_leap} = Timestamp.parse("2017-01-01T00:00:00Z")

    assert Timestamp.compare(before_leap, leap) == :lt
    assert Timestamp.compare(leap, leap_fraction) == :lt
    assert Timestamp.compare(leap_fraction, after_leap) == :lt
  end

  test "rejects offsets, lowercase markers, impossible dates, misplaced leap seconds, and terms" do
    invalid = [
      "2026-08-25T10:00:00+00:00",
      "2026-08-25t10:00:00z",
      "2025-02-29T10:00:00Z",
      "2016-12-30T23:59:60Z",
      "2016-12-31T12:00:60Z",
      "2016-12-31T23:59:61Z"
    ]

    for value <- invalid do
      assert {:error, %Error{code: :timestamp_invalid, subject: ["timestamp"]}} =
               Timestamp.parse(value)
    end

    assert {:error, %Error{code: :invalid_type, subject: ["timestamp"]}} = Timestamp.parse(1)
  end
end
