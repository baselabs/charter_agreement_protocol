defmodule CharterAgreementProtocol.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/baselabs/charter_agreement_protocol"

  def project do
    [
      app: :charter_agreement_protocol,
      version: @version,
      elixir: "~> 1.20",
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      name: "Charter Agreement Protocol",
      description:
        "Portable, non-authorizing charter-agreement format and verification protocol.",
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [
        summary: [threshold: 100],
        ignore_modules: [
          CharterAgreementProtocol.AcceptanceFixture,
          CharterAgreementProtocol.ChainFixture,
          CharterAgreementProtocol.CharterRevisionFixture,
          CharterAgreementProtocol.ConformanceTest.Builder,
          CharterAgreementProtocol.DescriptorFixture,
          CharterAgreementProtocol.TerminationFixture
        ]
      ],
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      dialyzer: [plt_core_path: "_build/plts", plt_local_path: "_build/plts"]
    ]
  end

  def cli do
    [preferred_envs: [audit: :test, quality: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [extra_applications: [:crypto]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.3", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["rjpalermo"],
      files: [
        "lib",
        "priv/conformance",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "NOTICE",
        "SECURITY.md",
        "docs/protocol.md",
        "docs/adr/no-versioning-rule.md"
      ],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Security policy" => "#{@source_url}/blob/main/SECURITY.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "NOTICE",
        "SECURITY.md",
        "docs/protocol.md",
        "docs/adr/no-versioning-rule.md"
      ]
    ]
  end

  defp aliases do
    [
      audit: ["hex.audit", "deps.unlock --check-unused", "deps.audit"],
      quality: [
        "hex.audit",
        "deps.unlock --check-unused",
        "deps.audit",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test --cover --seed 42",
        "dialyzer",
        "docs --warnings-as-errors"
      ]
    ]
  end
end
