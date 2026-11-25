defmodule CharterAgreementProtocol.ReleaseCompatibility do
  @moduledoc false

  alias CharterAgreementProtocol.Canonicalization

  @baselines ~w(hex:1.0.0 npm:1.0.0)
  @entry_points ~w(corpus_runner public_api)
  @non_errors ~w(valid raised unsupported)

  @directions %{
    admission: [:red_to_green],
    verdict_narrowing: [:green_to_red],
    resource_boundary: [:green_to_red, :red_to_green],
    typed_error: [:crash_to_typed],
    error_code_change: [:red_to_red],
    output_change: [:green_to_green],
    unsupported_in_baseline: [:baseline_unsupported]
  }

  def verify!(row, version, semantics, live_digest, root) do
    expected_digest = released_digest(root, version) || live_digest

    if row.verification_semantics != semantics,
      do: raise("current compatibility row does not match the verification semantics")

    if row.census_digest != expected_digest,
      do: raise("compatibility census for #{version}: #{row.census_digest} != #{expected_digest}")

    Enum.each(row.transitions, &verify_transition!/1)
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

      Map.merge(plain, %{"operation" => transition.operation, "witnesses" => witnesses})
    else
      plain
    end
  end

  def verify_npm_witnesses!(row, pinned_metadata) do
    {%{"package_version" => version, "compatibility" => rows}, :metadata, rest} =
      :json.decode(pinned_metadata, :metadata, %{null: nil})

    if String.trim(rest) != "", do: raise("pinned verifier source metadata has trailing data")

    # Select the same row as the TypeScript reverse gate at the pinned source.
    pinned = Enum.find(rows, &(version in &1["package_versions"]))
    [current] = manifest([row])

    unless npm_witnesses!(current) == npm_witnesses!(pinned) do
      raise "npm compatibility witnesses differ from the pinned TypeScript verifier source"
    end

    :ok
  end

  defp npm_witnesses!(%{"transitions" => transitions}) do
    witnesses = Enum.flat_map(transitions, &npm_transition/1)
    {:ok, bytes} = Canonicalization.encode_plain(witnesses)
    bytes
  end

  defp npm_transition(transition) do
    witnesses = Enum.filter(Map.get(transition, "witnesses", []), &npm_witness?/1)

    if witnesses == [], do: [], else: [Map.put(transition, "witnesses", witnesses)]
  end

  defp npm_witness?(%{"baselines" => baselines}) do
    Enum.any?(baselines, &String.starts_with?(&1, "npm:"))
  end

  def verify_corpus_witnesses!(row, cases) do
    operations = Map.new(cases, &{"corpus_runner/" <> &1["id"], &1["surface"]})

    for transition <- row.transitions,
        group <- Map.get(transition, :witnesses, []),
        group.entry_point == "corpus_runner",
        id <- group.cases do
      verify_operation!("corpus_runner/" <> id, transition.operation, operations)
    end

    :ok
  end

  def verify_reverse!(row, baseline, actual, candidate) do
    operations = operations(candidate)

    if operations(actual) != operations do
      raise "reverse differential #{baseline}: case IDs or operations do not match"
    end

    expected = reverse_witnesses(row, baseline, operations)

    changed =
      for {id, %{"value" => before}} <- actual,
          %{"value" => later} = Map.fetch!(candidate, id),
          before != later,
          into: %{},
          do: {id, change(before, later)}

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

  defp operations(observed) do
    Map.new(observed, fn {id, %{"operation" => operation}} -> {id, operation} end)
  end

  defp change(
         %{"status" => "valid", "output" => before},
         %{"status" => "valid", "output" => later}
       ),
       do: {"valid", "valid", %{"before" => before, "after" => later}}

  defp change(before, later), do: {verdict(before), verdict(later), nil}

  defp verdict(%{"status" => "valid"}), do: "valid"
  defp verdict(code) when is_binary(code), do: code

  defp reverse_witnesses(row, baseline, operations) do
    Enum.reduce(row.transitions, %{}, fn transition, collected ->
      witnesses = transition_witnesses!(transition)

      Enum.reduce(witnesses, collected, fn group, acc ->
        add_witnesses(group, acc, baseline, transition.operation, operations)
      end)
    end)
  end

  defp transition_witnesses!(%{witnesses: [_first | _rest] = witnesses} = transition) do
    verify_transition!(transition)
    witnesses
  end

  defp transition_witnesses!(transition) do
    raise "reverse differential: transition has no witnesses: #{transition.description}"
  end

  defp add_witnesses(group, acc, baseline, operation, operations) do
    if baseline in group.baselines do
      pair = {group.from, group.to, Map.get(group, :outputs)}

      Enum.reduce(group.cases, acc, fn id, witnesses ->
        key = group.entry_point <> "/" <> id
        verify_operation!(key, operation, operations)
        add_witness(key, witnesses, pair, baseline)
      end)
    else
      acc
    end
  end

  defp verify_operation!(key, operation, operations) do
    unless Map.get(operations, key) == operation do
      raise "reverse differential: witness #{key} does not name operation #{operation}"
    end
  end

  defp add_witness(id, acc, pair, baseline) do
    if Map.has_key?(acc, id) do
      raise "reverse differential #{baseline}: duplicate witness #{id}"
    end

    Map.put(acc, id, pair)
  end

  defp verify_transition!(%{class: class, direction: direction} = transition) do
    unless direction in Map.get(@directions, class, []) do
      raise "incompatible release transition #{inspect(class)}: #{inspect(direction)}"
    end

    witnesses = Map.get(transition, :witnesses, [])

    if witnesses != [] and not nonempty_text?(Map.get(transition, :operation)) do
      raise "reverse differential: transition with witnesses requires an operation"
    end

    Enum.each(witnesses, &verify_witness!(&1, direction))
  end

  defp verify_witness!(
         %{baselines: baselines, cases: [_ | _], entry_point: entry_point, from: from, to: to} =
           witness,
         direction
       )
       when entry_point in @entry_points do
    if baselines == [] or Enum.any?(baselines, &(&1 not in @baselines)) do
      raise "reverse differential: unknown or empty baseline group"
    end

    unless witness_direction(from, to, Map.get(witness, :outputs)) == direction do
      raise "reverse differential: witness #{inspect({from, to})} disagrees with #{direction}"
    end
  end

  defp verify_witness!(_group, _direction) do
    raise "reverse differential: witness requires an entry point and case IDs"
  end

  defp witness_direction("valid", "valid", %{"before" => before, "after" => later} = outputs)
       when before != later and map_size(outputs) == 2,
       do: :green_to_green

  defp witness_direction(from, to, nil) do
    case {outcome_kind(from), outcome_kind(to)} do
      {"unsupported", kind} when kind in ["valid", :typed] -> :baseline_unsupported
      {"raised", :typed} -> :crash_to_typed
      {"valid", :typed} -> :green_to_red
      {:typed, "valid"} -> :red_to_green
      {:typed, :typed} when from != to -> :red_to_red
      _other -> nil
    end
  end

  defp witness_direction(_from, _to, _outputs), do: nil

  defp outcome_kind(value) when value in @non_errors, do: value
  defp outcome_kind(value) when is_binary(value) and byte_size(value) > 0, do: :typed
  defp outcome_kind(_value), do: nil

  defp nonempty_text?(value), do: is_binary(value) and byte_size(value) > 0

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
