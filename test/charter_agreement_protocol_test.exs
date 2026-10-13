defmodule CharterAgreementProtocolTest do
  use ExUnit.Case, async: true

  # Every `iex>` example in these modules' docs runs here, so a doc example
  # that stops matching the code fails the suite.
  doctest CharterAgreementProtocol
  doctest CharterAgreementProtocol.Algorithm
  doctest CharterAgreementProtocol.Capability
  doctest CharterAgreementProtocol.Capability.Profile
  doctest CharterAgreementProtocol.ChainFacts
  doctest CharterAgreementProtocol.Error
  doctest CharterAgreementProtocol.Facts
  doctest CharterAgreementProtocol.Limits
end
