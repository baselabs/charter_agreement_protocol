# The TypeScript verifier source that CAP's cross-implementation gates run,
# materialized from the commit pinned in priv/verifier-source.json into
# _build/verifier-source/. The published npm package is built from that
# repository, so the gates exercise the code that ships rather than a copy.
# Gates and the test helper load this file with Code.require_file/2;
# `mix verifier.source` (scripts/materialize_verifier_source.exs) runs it.
#
# The pin must be reachable from the repository's main branch as freshly
# fetched from its public origin (never a local branch: a sibling checkout's
# unpushed commit is invisible to CI), and it must descend from the pin at
# HEAD (pins move forward only). A sibling checkout at
# ../charter_agreement_protocol_typescript supplies objects when present.
# The tree is extracted with `git archive`, its tar commit id must equal the
# pin, and every file's blob id must equal the pinned tree's, so no working
# tree, attribute or export filter can substitute content.

defmodule CharterAgreementProtocol.VerifierSource do
  @moduledoc false

  @root Path.expand("..", __DIR__)
  @pin_path "priv/verifier-source.json"
  @cache "_build/verifier-source.git"
  @target "_build/verifier-source"
  @sibling "../charter_agreement_protocol_typescript"

  @doc "The materialized source directory, relative to the repository root."
  def path, do: @target

  @doc """
  Raises unless the materialized tree was built from the current pin. Gates
  call this first, so a tree left from an earlier pin can never stand in.
  """
  def current! do
    %{"commit" => commit} = pin!()

    case File.read(Path.join(@root, stamp_path())) do
      {:ok, ^commit} ->
        :ok

      _stale_or_missing ->
        raise("verifier source: #{@target} is not built from the pin; run mix verifier.source")
    end
  end

  defp stamp_path, do: @target <> ".commit"

  def run(args) do
    cached? = "--cached" in args
    %{"repository" => repository, "commit" => commit} = pin!()
    cache = Path.join(@root, @cache)
    ensure_cache!(cache)
    fetch_sibling(cache)

    unless cached? do
      git!(cache, [
        "fetch",
        "--quiet",
        "--no-tags",
        repository,
        "+refs/heads/main:refs/remotes/origin/main"
      ])

      reachable!(
        cache,
        commit,
        "refs/remotes/origin/main",
        "the pinned commit is not on #{repository} main"
      )

      forward_only!(cache, commit)
    end

    object_present!(cache, commit)
    materialize!(cache, commit)
    IO.puts("verifier source: #{commit} materialized at #{@target}")
  end

  def pin! do
    case @root |> Path.join(@pin_path) |> File.read!() |> :json.decode() do
      %{"repository" => "https://" <> _ = repository, "commit" => commit} = pin
      when byte_size(commit) == 40 and map_size(pin) == 2 ->
        if commit =~ ~r/\A[0-9a-f]{40}\z/,
          do: %{"repository" => repository, "commit" => commit},
          else: raise("verifier source pin: commit is not a full lowercase SHA-1")

      _other ->
        raise("verifier source pin: expected exactly {repository, commit} in #{@pin_path}")
    end
  end

  defp ensure_cache!(cache) do
    unless File.dir?(cache) do
      File.mkdir_p!(Path.dirname(cache))
      {_out, 0} = System.cmd("git", ["init", "--quiet", "--bare", cache])
    end
  end

  # Objects only: refs land under refs/sibling/, never refs/remotes/origin/.
  defp fetch_sibling(cache) do
    sibling = Path.expand(@sibling, @root)

    if File.dir?(Path.join(sibling, ".git")) do
      System.cmd(
        "git",
        [
          "--git-dir",
          cache,
          "fetch",
          "--quiet",
          "--no-tags",
          sibling,
          "+refs/heads/*:refs/sibling/*"
        ],
        stderr_to_stdout: true
      )
    end
  end

  defp object_present!(cache, commit) do
    case System.cmd("git", ["--git-dir", cache, "cat-file", "-e", commit <> "^{commit}"],
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        :ok

      _missing ->
        raise("verifier source: commit #{commit} is not in the local cache; run without --cached")
    end
  end

  defp reachable!(cache, commit, ref, message) do
    case System.cmd("git", ["--git-dir", cache, "merge-base", "--is-ancestor", commit, ref],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> :ok
      _not_ancestor -> raise("verifier source: #{message} (#{commit})")
    end
  end

  # The pin recorded at HEAD, when there is one, must be an ancestor of the new pin.
  # The newest pin change must move forward: the pin being materialized must
  # descend from the newest committed pin, and the newest committed pin from
  # the distinct pin before it on the first-parent history. A backward pin
  # therefore fails in its own CI run, where the working tree equals HEAD,
  # and a later forward commit repairs it. This needs a full git clone.
  defp forward_only!(cache, commit) do
    [newest | older] = Enum.dedup([commit | committed_pins()])

    case older do
      [previous | _rest] ->
        reachable!(
          cache,
          previous,
          newest,
          "the newest pin change moves backward: #{newest} does not descend from"
        )

      [] ->
        :ok
    end
  end

  # Pin values along the first-parent history, newest first.
  defp committed_pins do
    case System.cmd("git", ["rev-parse", "--is-inside-work-tree"],
           cd: @root,
           stderr_to_stdout: true
         ) do
      {"true\n", 0} -> :ok
      _not_a_checkout -> raise("verifier source: the pin history check needs a git checkout")
    end

    case System.cmd("git", ["rev-parse", "--is-shallow-repository"], cd: @root) do
      {"false\n", 0} ->
        :ok

      _shallow ->
        raise("verifier source: the pin history check needs a full clone (fetch-depth 0)")
    end

    {log, 0} =
      System.cmd("git", ["log", "--first-parent", "--format=%H", "--", @pin_path], cd: @root)

    log |> String.split() |> Enum.flat_map(&pin_at/1)
  end

  # A commit in the log either changed the pin file or deleted it.
  defp pin_at(sha) do
    case System.cmd("git", ["cat-file", "-e", "#{sha}:#{@pin_path}"],
           cd: @root,
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        case System.cmd("git", ["show", "#{sha}:#{@pin_path}"], cd: @root, stderr_to_stdout: true) do
          {bytes, 0} -> [Map.fetch!(:json.decode(bytes), "commit")]
          {out, status} -> raise("verifier source: git show failed at #{sha} (#{status}): #{out}")
        end

      _deleted_at_sha ->
        []
    end
  end

  defp materialize!(cache, commit) do
    staging = Path.join(@root, "#{@target}.staging-#{System.unique_integer([:positive])}")
    archive = staging <> ".tar"
    File.mkdir_p!(staging)

    try do
      git!(cache, ["archive", "--format=tar", "--output", archive, commit])

      {stamp, 0} = tar_commit_id(archive)

      if String.trim(stamp) != commit,
        do: raise("verifier source: archive commit id #{String.trim(stamp)} != pin #{commit}")

      {_out, 0} = System.cmd("tar", ["-x", "-f", archive, "-C", staging])
      blobs_match!(cache, commit, staging)
      File.rm(Path.join(@root, stamp_path()))
      swap_in!(staging)
      File.write!(Path.join(@root, stamp_path()), commit)
    after
      File.rm(archive)
      File.rm_rf(staging)
    end
  end

  defp tar_commit_id(archive) do
    System.cmd("sh", ["-c", "git get-tar-commit-id < \"$1\"", "sh", archive])
  end

  defp blobs_match!(cache, commit, staging) do
    {listing, 0} = System.cmd("git", ["--git-dir", cache, "ls-tree", "-r", "-z", commit])

    expected =
      listing
      |> String.split(<<0>>, trim: true)
      |> Map.new(fn line ->
        [meta, path] = String.split(line, "\t", parts: 2)
        [_mode, _type, blob] = String.split(meta, " ")
        {path, blob}
      end)

    extracted =
      staging
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, staging))
      |> MapSet.new()

    if extracted != MapSet.new(Map.keys(expected)),
      do: raise("verifier source: extracted file set differs from the pinned tree")

    Enum.each(expected, fn {path, blob} ->
      {actual, 0} = System.cmd("git", ["hash-object", "--no-filters", Path.join(staging, path)])

      if String.trim(actual) != blob,
        do: raise("verifier source: #{path} does not match its pinned blob")
    end)
  end

  defp swap_in!(staging) do
    target = Path.join(@root, @target)
    retired = "#{target}.retired-#{System.unique_integer([:positive])}"
    if File.exists?(target), do: File.rename!(target, retired)
    File.rename!(staging, target)
    File.rm_rf!(retired)
  end

  defp git!(cache, args) do
    case System.cmd("git", ["--git-dir", cache | args], stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, status} -> raise("verifier source: git #{hd(args)} failed (#{status})\n#{out}")
    end
  end
end
