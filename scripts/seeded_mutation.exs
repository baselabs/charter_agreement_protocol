# Shared by the gate scripts that prove their comparison can fail by running a
# mutated scratch copy of the TypeScript verifier. Load it with
# `Code.require_file("seeded_mutation.exs", __DIR__)`.
#
# The rule every seeded red follows: the anchor occurs exactly once in the file
# and the replacement differs from it, so a seed can never silently become a
# no-op when the source it targets is reworded.

defmodule CharterAgreementProtocol.SeededMutation do
  @moduledoc false

  def apply_once!(path, from, to) do
    if from == to, do: raise("seed replacement equals its anchor: #{path}")
    bytes = File.read!(path)

    case length(:binary.matches(bytes, from)) do
      1 -> File.write!(path, String.replace(bytes, from, to))
      count -> raise("seed anchor occurs #{count} times, expected once: #{path}")
    end
  end

  def temporary!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "cap-#{label}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
