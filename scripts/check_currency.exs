# Dependency currency gate: fails on any resolvable dependency drift.
#
# Contract: runs in the caller's working directory — this script never
# changes directories; point it at a checkout by invoking from there
# (`mix currency.check`, or `mix run --no-start scripts/check_currency.exs`
# from the project root).
#
# Classification is on the rendered hex.outdated table, never on the
# command's exit code: `mix hex.outdated` exits nonzero both on drift and on
# lookup failure, so the exit code cannot distinguish them. Table rows are
# padded with trailing whitespace, so every status match is anchored on
# \s*$ — a bare $ fails open. A failed hex.pm lookup renders no table, and
# no table means currency is UNVERIFIED, never green.
#
# Cross-platform: `mix` is spawned through cmd on Windows (mix.bat is not
# directly executable), so no POSIX shell is required on any host.

windows? = match?({:win32, _}, :os.type())
{mix_exec, mix_prefix} = if windows?, do: {"cmd", ["/c", "mix"]}, else: {"mix", []}

outdated = fn args ->
  {out, _exit} =
    System.cmd(mix_exec, mix_prefix ++ ["hex.outdated" | args],
      stderr_to_stdout: true,
      into: ""
    )

  out
end

out = outdated.(["--all"])
lines = String.split(out, "\n")

table_rendered? = Enum.any?(lines, &Regex.match?(~r/^Dependency\s+Only/, &1))

unless table_rendered? do
  IO.puts(:stderr, "currency unverified: mix hex.outdated --all rendered no result table")
  IO.puts(:stderr, out)
  System.halt(1)
end

drift = Enum.filter(lines, &Regex.match?(~r/Update possible\s*$/, &1))

if drift != [] do
  IO.puts(:stderr, "dependency drift: resolvable updates exist for the rows below")
  Enum.each(drift, &IO.puts(:stderr, &1))
end

rejected =
  lines
  |> Enum.filter(&Regex.match?(~r/Update not possible\s*$/, &1))
  |> Enum.map(&(String.split(&1, ~r/\s+/, parts: 2) |> hd()))

Enum.each(rejected, fn pkg ->
  IO.puts(:stderr, "--- #{pkg}: update rejected by the requirement chain")
  IO.puts(:stderr, outdated.([pkg]))
end)

if drift != [] do
  System.halt(1)
end
