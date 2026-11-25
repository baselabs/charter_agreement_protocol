defmodule CharterAgreementProtocol.ReleaseCompatibility do
  @moduledoc false

  @directions %{
    admission: [:red_to_green],
    verdict_narrowing: [:green_to_red],
    resource_boundary: [:green_to_red, :red_to_green],
    typed_error: [:crash_to_typed],
    error_code_change: [:red_to_red]
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
