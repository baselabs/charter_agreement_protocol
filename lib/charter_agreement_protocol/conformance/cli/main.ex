defmodule CharterAgreementProtocol.Conformance.Cli.Main do
  @moduledoc "CAP never authorizes. One-line escript process adapter."

  alias CharterAgreementProtocol.Conformance.Cli

  @spec main([binary()]) :: no_return()
  def main(arguments), do: System.halt(Cli.run(arguments))
end
