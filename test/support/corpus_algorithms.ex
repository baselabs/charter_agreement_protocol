defmodule CharterAgreementProtocol.ConformanceTest.CorpusAlgorithms do
  @moduledoc false

  def select(cases, group) do
    Enum.filter(cases, fn one ->
      ml_dsa?(one["input"]) == (group == :ml_dsa)
    end)
  end

  defp ml_dsa?(input) when is_map(input) do
    input |> Map.drop(["profile"]) |> Map.values() |> Enum.any?(&ml_dsa?/1)
  end

  defp ml_dsa?(input) when is_list(input), do: Enum.any?(input, &ml_dsa?/1)
  defp ml_dsa?("ML-DSA-" <> _parameter), do: true

  defp ml_dsa?(input) when is_binary(input) do
    case String.split(input, ".") do
      [header, _payload, _signature] ->
        with {:ok, bytes} <- Base.url_decode64(header, padding: false),
             {:ok, value} <- CharterAgreementProtocol.Json.decode(bytes) do
          {:object, members} = value

          case List.keyfind(members, "alg", 0) do
            {"alg", {:string, "ML-DSA-" <> _parameter}} -> true
            _other -> false
          end
        else
          _other -> false
        end

      _other ->
        false
    end
  end

  defp ml_dsa?(_input), do: false
end
