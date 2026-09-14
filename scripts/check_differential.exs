# Randomized differential testing between the Elixir reference decoder and
# the TypeScript verifier's decoder over generated JSON texts. The fixed
# certified corpus anchors known behavior; this gate feeds freshly generated
# inputs to both implementations and requires byte-identical projections.
#
# A seeded red proves the comparison can fail: a mutated TypeScript copy that
# collapses float-typed numbers to integer tags must disagree.
#
# Run: mix run --no-start scripts/check_differential.exs

alias CharterAgreementProtocol.{Base64Url, Canonicalization, Json}

defmodule CharterAgreementProtocol.DifferentialGate do
  @moduledoc false

  @case_count 300

  def run do
    texts = Enum.map(1..@case_count, &generate_text/1)
    input_path = Path.join(System.tmp_dir!(), "cap-differential-inputs.jsonl")
    File.write!(input_path, Enum.join(texts, "\n"))

    elixir_projection =
      texts |> Enum.map(&project/1) |> tagged() |> Canonicalization.encode() |> elem(1)

    typescript_projection = run_typescript(Path.absname("verifier"), input_path)

    if elixir_projection != typescript_projection do
      raise "differential gate: Elixir and TypeScript projections diverge"
    end

    IO.puts("differential gate: ok cases=#{@case_count}")

    seeded_red!(input_path)
    IO.puts("differential gate: seeded red fired")
  end

  defp generate_text(seed) do
    :rand.seed(:exsss, seed)
    value = generate_value(3)
    Canonicalization.encode(value) |> elem(1)
  end

  defp generate_value(depth) do
    case :rand.uniform(7) do
      1 ->
        :null

      2 ->
        {:boolean, :rand.uniform(2) == 1}

      3 ->
        {:integer, :rand.uniform(9_007_199_254_740_991) - 1}

      4 ->
        {:float, :rand.normal() * :rand.uniform(1000)}

      5 ->
        {:string, random_string()}

      6 when depth > 1 ->
        {:array, for(_ <- 1..:rand.uniform(4), do: generate_value(depth - 1))}

      _n when depth > 1 ->
        {:object, for(_ <- 1..:rand.uniform(4), do: {random_string(), generate_value(depth - 1)})}

      _ ->
        {:integer, :rand.uniform(100)}
    end
  end

  defp random_string do
    alphabet = Enum.to_list(?a..?z) ++ Enum.to_list(?A..?Z) ++ Enum.to_list(?0..?9) ++ ~c" .-_"

    for(_ <- 1..:rand.uniform(12), do: Enum.random(alphabet))
    |> :binary.list_to_bin()
  end

  defp tagged(list) when is_list(list), do: {:array, Enum.map(list, &tagged/1)}

  defp tagged(%{} = value),
    do: {:object, Enum.map(value, fn {key, item} -> {to_string(key), tagged(item)} end)}

  defp tagged(value) when is_binary(value), do: {:string, value}
  defp tagged(value) when is_integer(value), do: {:integer, value}
  defp tagged(value) when is_float(value), do: {:float, value}
  defp tagged(value) when is_boolean(value), do: {:boolean, value}
  defp tagged(nil), do: :null

  # Mirrors Conformance.Runner's json.decode projection and the TypeScript
  # verifier's jsonProjection onto the same canonical shape.
  defp project(text) do
    case Json.decode(text) do
      {:ok, value} -> %{"status" => "valid", "output" => project_value(value)}
      {:error, error} -> %{"status" => "invalid", "error_code" => error.code}
    end
  end

  defp project_value(:null), do: %{"tag" => "null"}
  defp project_value({:boolean, value}), do: %{"tag" => "boolean", "value" => value}
  defp project_value({:integer, value}), do: %{"tag" => "integer", "value" => value}
  defp project_value({:float, value}), do: %{"tag" => "float", "value" => value}
  defp project_value({:string, value}), do: %{"tag" => "string", "value" => value}

  defp project_value({:array, values}),
    do: %{"tag" => "array", "items" => Enum.map(values, &project_value/1)}

  defp project_value({:object, members}) do
    %{"tag" => "object", "members" => Enum.map(members, fn {k, v} -> [k, project_value(v)] end)}
  end

  defp run_typescript(directory, input_path) do
    {output, status} =
      System.cmd("node", ["--experimental-strip-types", "--no-warnings", "diff.mjs", input_path],
        cd: directory,
        stderr_to_stdout: true
      )

    if status != 0, do: raise("TypeScript differential harness failed\n#{output}")
    String.trim_trailing(output)
  end

  defp seeded_red!(input_path) do
    directory = Path.join(System.tmp_dir!(), "cap-differential-red")
    File.rm_rf!(directory)
    File.cp_r!("verifier", directory)

    mutated = directory |> Path.join("core.ts") |> File.read!()

    mutated =
      String.replace(
        mutated,
        "const boxed = /[.eE]/.test(literal)",
        "const boxed = /never-floats/"
      )

    File.write!(Path.join(directory, "core.ts"), mutated)

    {output, status} =
      System.cmd("node", ["--experimental-strip-types", "--no-warnings", "diff.mjs", input_path],
        cd: directory,
        stderr_to_stdout: true
      )

    if status != 0, do: raise("seeded red harness failed\n#{output}")

    elixir_projection =
      input_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&project/1)
      |> tagged()
      |> Canonicalization.encode()
      |> elem(1)

    if elixir_projection == output,
      do: raise("differential seeded red did not fire: float-collapse undetected")

    File.rm_rf!(directory)
  end
end

CharterAgreementProtocol.DifferentialGate.run()
