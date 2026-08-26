defmodule CharterAgreementProtocol.MixProject do
  use Mix.Project

  @version "0.2.0"
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
      escript: [main_module: CharterAgreementProtocol.Conformance.Cli.Main],
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
          CharterAgreementProtocol.Conformance.Cli,
          CharterAgreementProtocol.Conformance.Cli.Main,
          CharterAgreementProtocol.DescriptorFixture,
          CharterAgreementProtocol.ReceiptFixture,
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
      {:agent_blueprint_protocol, "== 0.1.1", only: [:dev, :test], runtime: false},
      {:bounded_authority_protocol, "== 0.1.2", only: [:dev, :test], runtime: false},
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
        "priv/release-metadata.json",
        ".formatter.exs",
        "mix.exs",
        "spec",
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "NOTICE",
        "SECURITY.md",
        "docs/protocol.md",
        "docs/errata.md",
        "docs/test-vectors.md",
        "docs/guides",
        "docs/notebooks",
        "docs/profiles/indexed-price.md",
        "docs/adr/no-versioning-rule.md",
        "docs/adr/conformance-release-candidate.md"
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
        "CONTRIBUTING.md",
        "LICENSE",
        "NOTICE",
        "SECURITY.md",
        "docs/protocol.md",
        "docs/errata.md",
        "docs/test-vectors.md",
        "docs/guides/getting-started.md",
        "docs/guides/overview.md",
        "docs/guides/artifacts.md",
        "docs/guides/verification.md",
        "docs/guides/receipts.md",
        "docs/guides/extensions.md",
        "docs/guides/security-model.md",
        "docs/guides/recipes.md",
        "docs/guides/conformance.md",
        "docs/guides/error-codes.md",
        "docs/guides/faq.md",
        "docs/notebooks/charter-tour.livemd",
        "docs/notebooks/fork-repair.livemd",
        "docs/profiles/indexed-price.md",
        "docs/adr/no-versioning-rule.md",
        "docs/adr/conformance-release-candidate.md",
        "spec/core.md",
        "spec/requirements.md",
        "spec/security-considerations.md",
        "spec/privacy-considerations.md",
        "spec/registry-policy.md",
        "spec/evolution.md"
      ],
      groups_for_extras: [
        Guides: [
          "docs/guides/getting-started.md",
          "docs/guides/overview.md",
          "docs/guides/artifacts.md",
          "docs/guides/verification.md",
          "docs/guides/receipts.md",
          "docs/guides/extensions.md",
          "docs/guides/security-model.md",
          "docs/guides/recipes.md",
          "docs/guides/conformance.md",
          "docs/guides/error-codes.md",
          "docs/guides/faq.md"
        ],
        Notebooks: [
          "docs/notebooks/charter-tour.livemd",
          "docs/notebooks/fork-repair.livemd"
        ],
        Reference: [
          "docs/protocol.md",
          "docs/errata.md",
          "docs/test-vectors.md",
          "docs/profiles/indexed-price.md",
          "docs/adr/no-versioning-rule.md",
          "docs/adr/conformance-release-candidate.md"
        ],
        Specification: [
          "spec/core.md",
          "spec/requirements.md",
          "spec/security-considerations.md",
          "spec/privacy-considerations.md",
          "spec/registry-policy.md",
          "spec/evolution.md"
        ]
      ],
      groups_for_modules: [
        Artifacts: [
          CharterAgreementProtocol.PartyDescriptor,
          CharterAgreementProtocol.DescriptorChain,
          CharterAgreementProtocol.CharterRevision,
          CharterAgreementProtocol.Acceptance,
          CharterAgreementProtocol.AcceptanceEquivocation,
          CharterAgreementProtocol.TerminationNotice,
          CharterAgreementProtocol.Receipt,
          CharterAgreementProtocol.ArtifactSet
        ],
        Facts: [
          CharterAgreementProtocol.DescriptorFacts,
          CharterAgreementProtocol.AcceptanceFacts,
          CharterAgreementProtocol.RevisionFacts,
          CharterAgreementProtocol.TerminationFacts,
          CharterAgreementProtocol.ChainFacts,
          CharterAgreementProtocol.ReceiptFacts
        ],
        Verification: [
          CharterAgreementProtocol.Chain,
          CharterAgreementProtocol.Facts,
          CharterAgreementProtocol.Signature,
          CharterAgreementProtocol.SigningInput,
          CharterAgreementProtocol.CompactJws
        ],
        Primitives: [
          CharterAgreementProtocol.Base64Url,
          CharterAgreementProtocol.Json,
          CharterAgreementProtocol.Canonicalization,
          CharterAgreementProtocol.Digest,
          CharterAgreementProtocol.Error,
          CharterAgreementProtocol.Limits,
          CharterAgreementProtocol.Timestamp,
          CharterAgreementProtocol.Schema
        ],
        Extensions: [
          CharterAgreementProtocol.Extension,
          CharterAgreementProtocol.ExtensionRegistry,
          CharterAgreementProtocol.RequirementMap
        ],
        Conformance: [
          CharterAgreementProtocol.Conformance.Corpus,
          CharterAgreementProtocol.Conformance.Runner,
          CharterAgreementProtocol.Conformance.Report,
          CharterAgreementProtocol.Conformance.Cli
        ]
      ]
    ]
  end

  defp aliases do
    [
      audit: ["hex.audit", "deps.unlock --check-unused", "deps.audit"],
      "conformance.verify": "run --no-start scripts/check_conformance.exs",
      "conformance.mutations": "run --no-start scripts/check_conformance_mutations.exs",
      "verifier.agreement": "run --no-start scripts/check_verifier_agreement.exs",
      "release.candidate": "run --no-start scripts/check_release_candidate.exs",
      quality: [
        "hex.audit",
        "deps.unlock --check-unused",
        "deps.audit",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test --cover --seed 42",
        "conformance.verify",
        "conformance.mutations",
        "verifier.agreement",
        "dialyzer",
        "docs --warnings-as-errors",
        "release.candidate"
      ]
    ]
  end
end
