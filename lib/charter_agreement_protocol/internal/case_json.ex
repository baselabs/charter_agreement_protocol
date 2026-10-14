defmodule CharterAgreementProtocol.Internal.CaseJson do
  @moduledoc false

  alias CharterAgreementProtocol.{Canonicalization, Error, Json}

  @spec encode(Json.value()) :: {:ok, binary()} | {:error, Error.t()}
  def encode(value) do
    with {:ok, _canonical} <- Canonicalization.encode(value) do
      {:ok, value |> encoded() |> IO.iodata_to_binary()}
    end
  end

  defp encoded({:object, members}) do
    inner =
      members
      |> Enum.sort_by(fn {name, _value} ->
        :unicode.characters_to_binary(name, :utf8, {:utf16, :big})
      end)
      |> Enum.map_intersperse(",", fn {name, value} ->
        [encoded({:string, name}), ":", encoded(value)]
      end)

    ["{", inner, "}"]
  end

  defp encoded({:array, values}),
    do: ["[", Enum.map_intersperse(values, ",", &encoded/1), "]"]

  defp encoded({:float, _float} = value) do
    {:ok, number} = Canonicalization.encode(value)
    if Regex.match?(~r/\A-?[0-9]+\z/, number), do: number <> ".0", else: number
  end

  defp encoded(value) do
    {:ok, bytes} = Canonicalization.encode(value)
    bytes
  end
end
