# Corpus witnesses use each package's own Runner.run/1. Host-record probes
# call the same public APIs separately. CI materializes the pinned TypeScript
# reference before this gate, so the published Hex outer pin has one source.
Code.require_file("release_compatibility.exs", __DIR__)
Code.require_file("reverse_corpus.exs", __DIR__)
Code.require_file("reverse_boundary.exs", __DIR__)
Code.require_file("verifier_source.exs", __DIR__)

defmodule CharterAgreementProtocol.ReverseDifferentialGate do
  @moduledoc false

  alias CharterAgreementProtocol.{
    ReleaseCompatibility,
    ReleaseIdentity,
    ReverseBoundary,
    ReverseCorpus,
    VerifierSource
  }

  alias Mix.Dep.Lock

  @version "1.0.0"
  @baseline "hex:" <> @version
  @inner_checksum "aed6035909e8af2cb2a67755748723ed2490bd1226dbe3424cbf1378fe6b456a"

  def run do
    root = Path.expand("../priv/conformance", __DIR__)
    corpus = ReverseCorpus.load!(root)
    version = Mix.Project.config()[:version]
    row = Enum.find(ReleaseIdentity.compatibility(), &(version in &1.package_versions))

    if row.census_digest != corpus.identity, do: raise("reverse differential: census mismatch")

    checked = ReverseCorpus.checked!(corpus)
    checked = ReverseCorpus.with_public_probes(checked, ReverseBoundary.outcomes(corpus.cases))
    observed = published(corpus.cases, outer_checksum!())
    count = ReleaseCompatibility.verify_reverse!(row, @baseline, observed, checked)
    IO.puts("reverse differential #{@baseline}: #{map_size(checked)} inputs, #{count} changes")
  end

  defp outer_checksum! do
    VerifierSource.current!()
    reference = Path.join(VerifierSource.path(), "reference.json")
    decoded = reference |> File.read!() |> :json.decode()

    %{"package" => "charter_agreement_protocol", "version" => @version} = decoded
    outer = Map.fetch!(decoded, "archive_sha256")

    unless outer =~ ~r/\A[0-9a-f]{64}\z/ do
      raise "invalid #{@baseline} archive checksum"
    end

    outer
  end

  defp published(cases, outer_checksum) do
    name = "cap-hex-" <> Base.url_encode64(:crypto.strong_rand_bytes(12))
    scratch = Path.join(System.tmp_dir!(), name)
    File.mkdir!(scratch)

    try do
      File.write!(Path.join(scratch, "mix.exs"), project())
      File.write!(Path.join(scratch, "cases.etf"), :erlang.term_to_binary(cases))
      File.write!(Path.join(scratch, "run.exs"), runner())

      for script <- ~w(reverse_boundary.exs reverse_corpus.exs) do
        File.cp!(Path.join(__DIR__, script), Path.join(scratch, script))
      end

      mix!(scratch, ["deps.get", "--only", "prod"])
      verify_lock!(scratch, outer_checksum)
      mix!(scratch, ["run", "--no-start", "run.exs"])
      scratch |> Path.join("outcomes.etf") |> ReverseCorpus.read_outcomes!()
    after
      File.rm_rf!(scratch)
    end
  end

  defp verify_lock!(scratch, outer_checksum) do
    expected =
      {:hex, :charter_agreement_protocol, @version, @inner_checksum, [:mix], [], "hexpm",
       outer_checksum}

    unless Lock.read(Path.join(scratch, "mix.lock")) == %{charter_agreement_protocol: expected} do
      raise "reverse differential #{@baseline}: published package lock checksums disagree"
    end
  end

  defp mix!(scratch, args) do
    {_output, status} =
      System.cmd("mix", args,
        cd: scratch,
        env: [
          {"MIX_ENV", "prod"},
          {"MIX_BUILD_PATH", nil},
          {"MIX_DEPS_PATH", nil},
          {"MIX_EXS", nil},
          {"MIX_PATH", nil},
          {"ERL_LIBS", nil}
        ],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "reverse differential #{@baseline}: mix #{hd(args)} failed (#{status})"
    end
  end

  defp project do
    """
    defmodule PublishedCap.MixProject do
      use Mix.Project

      def project do
        [
          app: :published_cap,
          version: "0.0.0",
          deps: [{:charter_agreement_protocol, "== #{@version}"}]
        ]
      end
    end
    """
  end

  defp runner do
    """
    alias CharterAgreementProtocol.{ReverseBoundary, ReverseCorpus}

    Code.require_file("reverse_corpus.exs", __DIR__)
    Code.require_file("reverse_boundary.exs", __DIR__)

    unless CharterAgreementProtocol.Capability.kat_verifies?("ML-DSA-65") do
      raise "published verifier requires ML-DSA-65"
    end

    cases = "cases.etf" |> File.read!() |> :erlang.binary_to_term([:safe])
    root = Application.app_dir(:charter_agreement_protocol, "priv/conformance")
    frozen = ReverseCorpus.load!(root)
    observed = ReverseCorpus.published!(frozen, cases)
    outcomes = ReverseCorpus.with_public_probes(observed, ReverseBoundary.outcomes(cases))

    ReverseCorpus.write_outcomes!("outcomes.etf", outcomes)
    """
  end
end

CharterAgreementProtocol.ReverseDifferentialGate.run()
