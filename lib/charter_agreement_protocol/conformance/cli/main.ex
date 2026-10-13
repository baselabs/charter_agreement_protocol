defmodule CharterAgreementProtocol.Conformance.Cli.Main do
  @moduledoc """
  The escript entry point for the conformance CLI.

  It never authorizes anything. Call
  `CharterAgreementProtocol.Conformance.Cli.run/1` from code instead.
  """

  alias CharterAgreementProtocol.Conformance.Cli

  @doc "Run `CharterAgreementProtocol.Conformance.Cli.run/1` and halt with its exit status."
  @spec main([binary()]) :: no_return()
  def main(arguments), do: System.halt(Cli.run(arguments))
end
