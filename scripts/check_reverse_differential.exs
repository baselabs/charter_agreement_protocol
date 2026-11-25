Code.require_file("release_compatibility.exs", __DIR__)
Code.require_file("reverse_boundary.exs", __DIR__)

defmodule CharterAgreementProtocol.ReverseDifferentialGate do
  @moduledoc false

  alias CharterAgreementProtocol.Conformance.Corpus
  alias CharterAgreementProtocol.{ReleaseCompatibility, ReleaseIdentity, ReverseBoundary}

  @baseline "hex:1.0.0"

  def run do
    root = Path.expand("../priv/conformance", __DIR__)
    {:ok, corpus} = Corpus.load(corpus_files(root))
    version = Mix.Project.config()[:version]
    row = Enum.find(ReleaseIdentity.compatibility(), &(version in &1.package_versions))

    if row.census_digest != corpus.identity, do: raise("reverse differential: census mismatch")

    expected = Map.new(corpus.cases, &{&1["id"], verdict(&1["expect"])})
    expected = Map.merge(expected, ReverseBoundary.outcomes(corpus.cases))
    observed = published(corpus.cases)
    count = ReleaseCompatibility.verify_reverse!(row, @baseline, observed, expected)
    IO.puts("reverse differential #{@baseline}: #{map_size(expected)} inputs, #{count} changes")
  end

  defp corpus_files(root) do
    root
    |> Path.join("{index.json,cases/*.json}")
    |> Path.wildcard()
    |> Map.new(&{Path.relative_to(&1, root), File.read!(&1)})
  end

  defp published(cases) do
    name = "cap-hex-" <> Base.url_encode64(:crypto.strong_rand_bytes(12))
    scratch = Path.join(System.tmp_dir!(), name)
    File.mkdir!(scratch)

    try do
      File.write!(Path.join(scratch, "mix.exs"), project())
      File.write!(Path.join(scratch, "cases.etf"), :erlang.term_to_binary(cases))
      File.write!(Path.join(scratch, "run.exs"), runner())
      boundary_script = "reverse_boundary.exs"
      File.cp!(Path.join(__DIR__, boundary_script), Path.join(scratch, boundary_script))
      mix!(scratch, ["deps.get", "--only", "prod"])
      mix!(scratch, ["run", "--no-start", "run.exs"])
      scratch |> Path.join("outcomes.json") |> File.read!() |> :json.decode()
    after
      File.rm_rf!(scratch)
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
        [app: :published_cap, version: "0.0.0", deps: [{:charter_agreement_protocol, "== 1.0.0"}]]
      end
    end
    """
  end

  defp runner do
    """
    alias CharterAgreementProtocol.Conformance.{Corpus, Runner}
    alias CharterAgreementProtocol.ReverseBoundary

    Code.require_file("reverse_boundary.exs", __DIR__)

    unless CharterAgreementProtocol.Capability.kat_verifies?("ML-DSA-65") do
      raise "published verifier requires ML-DSA-65"
    end

    cases = "cases.etf" |> File.read!() |> :erlang.binary_to_term([:safe])

    supported? = fn one ->
      one["surface"] in Corpus.surfaces() and
        not (one["surface"] == "signing.prepare" and one["input"]["kind"] == "party_replacement")
    end

    {supported, unsupported} = Enum.split_with(cases, supported?)
    outcomes = Map.new(unsupported, &{&1["id"], "unsupported"})

    observed =
      struct(Corpus, cases: supported)
      |> Runner.run()
      |> Map.new(fn %{id: id, actual: actual} ->
        {id, if(actual["status"] == "valid", do: "valid", else: Map.fetch!(actual, "error_code"))}
      end)

    outcomes = outcomes |> Map.merge(observed) |> Map.merge(ReverseBoundary.outcomes(cases))
    File.write!("outcomes.json", :json.encode(outcomes))
    """
  end

  defp verdict(%{"status" => "valid"}), do: "valid"
  defp verdict(%{"status" => "invalid", "error_code" => code}), do: code
end

CharterAgreementProtocol.ReverseDifferentialGate.run()
