defmodule CharterAgreementProtocol.Conformance.RunnerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CharterAgreementProtocol.{
    Capability.Profile,
    Conformance.Corpus,
    Conformance.Runner,
    Limits
  }

  @json_types [nil, false, 0, 1.0, "bad", [], %{}]

  property "every surface and input member returns a typed outcome for every JSON type" do
    cases = cases()

    assert Enum.sort(Enum.uniq_by(cases, & &1["surface"]) |> Enum.map(& &1["surface"])) ==
             Enum.sort(Corpus.surfaces())

    check all(value <- json_value(), max_runs: 5) do
      for one <- cases,
          path <- paths(one["input"]),
          replacement <- [value | @json_types] do
        input = replace(one["input"], path, replacement)
        assert_typed(%{one | "input" => input})
      end
    end
  end

  test "profile errors, zero governing limits and absent receipt contexts return typed errors" do
    cases = cases()

    for surface <- ~w(party_descriptor.verify acceptance.verify termination.verify receipt.verify),
        profile <- [%{"algorithms" => []}, %{"algorithms" => nil}, %{"revisions" => nil}] do
      one = Enum.find(cases, &(&1["surface"] == surface))
      assert_code(put_in(one, ["input", "profile"], profile), "invalid_profile")
    end

    governing = Enum.find(cases, &(&1["surface"] == "governing_revision"))
    assert_code(put_in(governing, ["input", "limits"], %{"max_bytes" => 0}), "limit_exceeded")
    receipt = Enum.find(cases, &(&1["surface"] == "receipt.verify"))

    for input <- [
          %{"compact" => receipt["input"]["compact"]},
          %{"compact" => receipt["input"]["compact"], "chain" => nil}
        ] do
      assert_code(%{receipt | "input" => input}, "invalid_type")
    end
  end

  defp cases do
    cases =
      Path.wildcard("priv/conformance/cases/*.json")
      |> Enum.flat_map(&(File.read!(&1) |> :json.decode() |> Map.fetch!("cases")))

    selected =
      Enum.uniq_by(
        cases,
        &{&1["surface"], Map.keys(&1["input"]), &1["input"]["kind"], &1["input"]["tag"]}
      )

    Enum.map(selected, fn one ->
      update_in(
        one,
        ["input"],
        &Map.merge(&1, %{
          "limits" =>
            Map.new(Map.from_struct(Limits.default()), fn {key, value} ->
              {Atom.to_string(key), value}
            end),
          "profile" => %{
            "algorithms" => Profile.full().algorithms,
            "revisions" => %{"min" => 1, "max" => 3}
          }
        })
      )
    end)
  end

  defp json_value do
    tree(
      one_of([
        constant(nil),
        boolean(),
        integer(-5..5),
        float(min: -5, max: 5),
        string(:alphanumeric, max_length: 5)
      ]),
      fn child ->
        one_of([
          list_of(child, max_length: 2),
          map_of(string(:alphanumeric, max_length: 4), child, max_length: 2)
        ])
      end
    )
  end

  defp paths(value) when is_map(value),
    do: [[] | Enum.flat_map(value, fn {key, item} -> Enum.map(paths(item), &[key | &1]) end)]

  defp paths(value) when is_list(value),
    do: [
      []
      | Enum.flat_map(Enum.with_index(value), fn {item, i} -> Enum.map(paths(item), &[i | &1]) end)
    ]

  defp paths(_value), do: [[]]

  defp replace(_value, [], replacement), do: replacement

  defp replace(value, [key | rest], replacement) when is_map(value),
    do: Map.update!(value, key, &replace(&1, rest, replacement))

  defp replace(value, [i | rest], replacement),
    do: List.update_at(value, i, &replace(&1, rest, replacement))

  defp assert_code(one, code),
    do: assert(actual(one) == %{"status" => "invalid", "error_code" => code})

  defp assert_typed(one) do
    case actual(one) do
      %{"status" => "valid", "output" => output} -> assert is_map(output)
      %{"status" => "invalid", "error_code" => code} -> assert is_binary(code) and code != ""
    end
  end

  defp actual(one) do
    [result] =
      Runner.run(%Corpus{
        cases: [one],
        index: %{},
        index_bytes: "",
        case_ids: MapSet.new(),
        identity: ""
      })

    result.actual
  end
end
