defmodule CharterAgreementProtocol.Architecture.DependencyDirectionTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.ArchitectureScan

  @forbidden_apps ~w(
    ash ash_replicant bandit bounded_authority capstan commerce_platform cowboy
    ecto ecto_sql finch mint navyler_cdc plug postgrex replicant req tesla
  )a
  @forbidden_roots ~w(
    Ash Bandit BoundedAuthority Capstan CommercePlatform Cowboy Ecto Finch Mint
    NavylerCdc Plug Postgrex Replicant Req Tesla
  )
  @source_roots ["lib", "test/support"]

  test "the runtime dependency graph points only to pure OTP crypto" do
    application = CharterAgreementProtocol.MixProject.application()
    refute Keyword.has_key?(application, :mod)
    assert Keyword.get(application, :extra_applications, []) == [:crypto]

    assert dependency_findings(Mix.Project.config()[:deps]) == []
    assert lock_findings(File.read!("mix.lock")) == []
    assert namespace_findings(source_files()) == []
  end

  test "the wall scan covers every declared compile-bearing source root" do
    files = source_files()
    assert Enum.any?(files, &String.starts_with?(&1, "lib/"))
    assert Enum.any?(files, &String.starts_with?(&1, "test/support/"))
  end

  test "forbidden, production, and runtime-enabled dependency mutations are rejected" do
    for deps <- [
          [{:bounded_authority, "~> 0.1"}],
          [{:req, "~> 0.5", only: [:dev, :test], runtime: false}],
          [{:stream_data, "~> 1.4", only: [:test], runtime: false}],
          [{:stream_data, "~> 1.4", only: [:dev, :test], runtime: true}]
        ] do
      assert dependency_findings(deps) != []
    end

    assert dependency_findings([{:stream_data, "~> 1.4", only: [:dev, :test], runtime: false}]) ==
             []
  end

  test "forbidden lock and namespace mutations are rejected without blocking sibling protocols" do
    assert lock_findings(~s(%{"bounded_authority": {:hex, :bounded_authority, "0.1.0"}})) != []
    assert lock_findings(~s(%{"stream_data": {:hex, :stream_data, "1.4.0"}})) == []

    assert source_namespace_findings("alias BoundedAuthority.Authority") != []
    assert source_namespace_findings("BoundedAuthorityProtocol.verify(bytes)") == []
    assert source_namespace_findings("AgentBlueprintProtocol.Digest.hash(:content, bytes)") == []
  end

  defp source_files do
    ArchitectureScan.source_files(@source_roots)
  end

  defp dependency_findings(deps) do
    for dep <- deps,
        {name, opts} = normalize_dep(dep),
        name in @forbidden_apps or Keyword.get(opts, :runtime) != false or
          Enum.sort(List.wrap(Keyword.get(opts, :only))) != [:dev, :test],
        do: name
  end

  defp normalize_dep({name, requirement, opts}) when is_binary(requirement) and is_list(opts),
    do: {name, opts}

  defp normalize_dep({name, opts}) when is_list(opts), do: {name, opts}
  defp normalize_dep({name, requirement}) when is_binary(requirement), do: {name, []}
  defp normalize_dep(other), do: {other, []}

  defp lock_findings(lock) do
    for app <- @forbidden_apps,
        Regex.match?(Regex.compile!(~s/"#{app}"\\s*:/), lock),
        do: app
  end

  defp namespace_findings(paths) do
    for path <- paths,
        reference <- ArchitectureScan.module_references(path),
        root = reference |> String.split(".") |> hd(),
        root in @forbidden_roots,
        do: {path, reference}
  end

  defp source_namespace_findings(source) do
    for root <- @forbidden_roots,
        Regex.match?(Regex.compile!("\\b" <> root <> "(?:\\.|\\b)"), source),
        not String.starts_with?(source, root <> "Protocol"),
        do: root
  end
end
