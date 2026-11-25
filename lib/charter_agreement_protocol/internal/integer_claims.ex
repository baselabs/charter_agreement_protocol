defmodule CharterAgreementProtocol.Internal.IntegerClaims do
  @moduledoc "CAP never authorizes. Integer token checks before claims encoding."

  alias CharterAgreementProtocol.Error

  @fields %{
    descriptor_publication: ~w(protocol_revision),
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
    with :ok <- fields(members, Map.get(@fields, kind, [])),
         :ok <- bindings(kind, List.keyfind(members, "abp_bindings", 0)) do
      quorum_thresholds(kind, members)
    end
  end

  def check(_kind, _value), do: :ok

  defp quorum_thresholds(:charter_revision, members) do
    case List.keyfind(members, "protocol_revision", 0) do
      {"protocol_revision", {:integer, 8}} -> revision_eight_thresholds(Map.new(members))
      _legacy -> :ok
    end
  end

  defp quorum_thresholds(_kind, _members), do: :ok

  defp revision_eight_thresholds(fields) do
    records = array_items(fields["party_replacements"])
    termination = object_members(fields["termination_rules"])
    assent = Enum.map(records, &Map.get(object_members(&1), "assent_quorum"))

    rules = [fields["acceptance_quorum"], termination["quorum"] | assent]

    if Enum.any?(rules, &float_threshold?/1),
      do: {:error, Error.new(:invalid_type, ["threshold"])},
      else: :ok
  end

  defp array_items({:array, items}), do: items
  defp array_items(_value), do: []

  defp object_members({:object, members}), do: Map.new(members)
  defp object_members(_value), do: %{}

  defp float_threshold?(value),
    do: match?({:float, _number}, Map.get(object_members(value), "threshold"))

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
