defmodule CharterAgreementProtocol.ReleaseCompatibility do
  @moduledoc false

  @baselines ~w(hex:1.0.0 npm:1.0.0)

  @directions %{
    admission: [:red_to_green],
    verdict_narrowing: [:green_to_red],
    resource_boundary: [:green_to_red, :red_to_green],
    typed_error: [:crash_to_typed],
    error_code_change: [:red_to_red],
    unsupported_in_baseline: [:baseline_unsupported]
  }

  def verify!(row, version, semantics, live_digest, root) do
    expected_digest = released_digest(root, version) || live_digest

    if row.verification_semantics != semantics,
      do: raise("current compatibility row does not match the verification semantics")

    if row.census_digest != expected_digest,
      do: raise("compatibility census for #{version}: #{row.census_digest} != #{expected_digest}")

    Enum.each(row.transitions, &verify_direction!/1)
    :ok
  end

  def manifest(rows) do
    Enum.map(rows, fn row ->
      %{
        "package_versions" => row.package_versions,
        "verification_semantics" => row.verification_semantics,
        "census_digest" => row.census_digest,
        "protocol_revisions" => row.protocol_revisions,
        "transitions" => Enum.map(row.transitions, &transition_manifest/1)
      }
    end)
  end

  defp transition_manifest(transition) do
    plain = %{
      "class" => Atom.to_string(transition.class),
      "direction" => Atom.to_string(transition.direction),
      "description" => transition.description
    }

    if Map.has_key?(transition, :witnesses) do
      witnesses =
        Enum.map(transition.witnesses, fn group ->
          Map.new(group, fn {key, value} -> {Atom.to_string(key), value} end)
        end)

      Map.put(plain, "witnesses", witnesses)
    else
      plain
    end
  end

  def verify_reverse!(row, baseline, actual, candidate) do
    if MapSet.new(Map.keys(actual)) != MapSet.new(Map.keys(candidate)) do
      raise "reverse differential #{baseline}: case IDs do not match"
    end

    expected = reverse_witnesses(row, baseline)

    changed =
      for {id, before} <- actual,
          after_verdict = Map.fetch!(candidate, id),
          before != after_verdict,
          into: %{},
          do: {id, {before, after_verdict}}

    if expected != changed do
      unexpected = Map.drop(changed, Map.keys(expected)) |> Enum.sort()
      stale = Map.drop(expected, Map.keys(changed)) |> Enum.sort()
      drift =
        Enum.filter(changed, fn {id, pair} ->
          Map.has_key?(expected, id) and expected[id] != pair
        end)

      raise """
      reverse differential #{baseline}: compatibility witnesses disagree
      unrecorded: #{inspect(unexpected, limit: :infinity)}
      no longer firing: #{inspect(stale, limit: :infinity)}
      outcome drift: #{inspect(Enum.sort(drift), limit: :infinity)}
      """
    end

    map_size(changed)
  end

  defp reverse_witnesses(row, baseline) do
    Enum.reduce(row.transitions, %{}, fn transition, collected ->
      case Map.fetch!(transition, :witnesses) do
        [_first | _rest] = witnesses ->
          Enum.reduce(witnesses, collected, &add_witnesses(&1, &2, baseline))

        [] ->
          raise "reverse differential: transition has no witnesses: #{transition.description}"
      end
    end)
  end

  defp add_witnesses(
         %{baselines: baselines, cases: [_first | _rest] = cases} = group,
         acc,
         baseline
       ) do
    if baselines == [] or Enum.any?(baselines, &(&1 not in @baselines)) do
      raise "reverse differential: unknown or empty baseline group"
    end

    if baseline in baselines do
      Enum.reduce(cases, acc, &add_witness(&1, &2, {group.from, group.to}, baseline))
    else
      acc
    end
  end

  defp add_witness(id, acc, pair, baseline) do
    if Map.has_key?(acc, id) do
      raise "reverse differential #{baseline}: duplicate witness #{id}"
    end

    Map.put(acc, id, pair)
  end

  defp verify_direction!(%{class: class, direction: direction}) do
    unless direction in Map.get(@directions, class, []) do
      raise "incompatible release transition #{inspect(class)}: #{inspect(direction)}"
    end
  end

  defp released_digest(root, version) do
    ref = "refs/tags/v#{version}"

    case System.cmd("git", ["show-ref", "--verify", "--quiet", ref],
           cd: root,
           stderr_to_stdout: true
         ) do
      {"", 0} -> read_release_index!(root, ref)
      {"", 1} -> nil
      {output, status} -> raise("git show-ref failed (#{status}): #{output}")
    end
  end

  defp read_release_index!(root, ref) do
    case System.cmd("git", ["show", "#{ref}:priv/conformance/index.json"],
           cd: root,
           stderr_to_stdout: true
         ) do
      {bytes, 0} -> bytes |> :json.decode() |> Map.fetch!("corpus_digest")
      {output, status} -> raise("git show failed (#{status}): #{output}")
    end
  end
end
