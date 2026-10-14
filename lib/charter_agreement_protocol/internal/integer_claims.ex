defmodule CharterAgreementProtocol.Internal.IntegerClaims do
  @moduledoc "CAP never authorizes. Integer token checks before claims encoding."

  alias CharterAgreementProtocol.Error

  @fields %{
    party_descriptor: ~w(protocol_revision descriptor_number),
    acceptance: ~w(protocol_revision revision_number),
    termination: ~w(protocol_revision),
    receipt: ~w(protocol_revision revision_number),
    charter_revision: ~w(protocol_revision revision_number)
  }

  @spec check(atom() | binary() | nil, term()) :: :ok | {:error, Error.t()}
  def check("cap+party", value), do: check(:party_descriptor, value)
  def check("cap+acceptance", value), do: check(:acceptance, value)
  def check("cap+termination", value), do: check(:termination, value)
  def check("cap+receipt", value), do: check(:receipt, value)

  def check(kind, {:object, members}) do
    with :ok <- fields(members, Map.get(@fields, kind, [])) do
      bindings(kind, List.keyfind(members, "abp_bindings", 0))
    end
  end

  def check(_kind, _value), do: :ok

  defp fields(members, names) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case List.keyfind(members, name, 0) do
        {^name, {:float, _value}} -> {:halt, {:error, Error.new(:invalid_type, [name])}}
        _other -> {:cont, :ok}
      end
    end)
  end

  defp bindings(:charter_revision, {"abp_bindings", {:array, values}}) do
    Enum.reduce_while(values, :ok, fn
      {:object, members}, :ok ->
        case fields(members, ["release_number"]) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      _other, :ok ->
        {:cont, :ok}
    end)
  end

  defp bindings(_kind, _value), do: :ok
end
