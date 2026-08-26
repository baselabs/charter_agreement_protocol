defmodule CharterAgreementProtocol.Conformance.RunnerReportCliTest do
  use ExUnit.Case, async: false

  alias CharterAgreementProtocol.Conformance.{Cli, Corpus, Report, Runner}
  alias CharterAgreementProtocol.Digest

  test "the shipped corpus executes every case and emits an identity-bound report" do
    assert {:ok, corpus} = Corpus.load(shipped_files())
    results = Runner.run(corpus)
    report = Report.build(corpus, results)

    assert report.agreement
    assert report.exit_status == 0
    assert report.total == 90
    assert report.agreed == 90
    assert report.disagreed == 0

    assert {:ok, bytes} = Report.to_bytes(corpus, results)
    assert bytes =~ ~s("corpus_digest":"#{corpus.identity}")
    assert bytes =~ ~s("registry_digest":"#{corpus.index["registry_digest"]}")
    assert bytes =~ ~s("index_sha256_base64url":"#{Report.index_identity(corpus.index_bytes)}")
  end

  test "one expectation flip makes the report disagree" do
    assert {:ok, corpus} = Corpus.load(shipped_files())

    [first | rest] = corpus.cases
    flipped = put_in(first, ["expect", "status"], "invalid")
    results = Runner.run(%{corpus | cases: [flipped | rest]})
    report = Report.build(corpus, results)

    refute report.agreement
    assert report.exit_status == 1
    assert report.disagreed == 1
  end

  test "JSON scalar projections and report floats are computed rather than read from expectations" do
    json_cases =
      for {id, text, output} <- [
            {"string", "\"value\"", %{"tag" => "string", "value" => "value"}},
            {"boolean", "true", %{"tag" => "boolean", "value" => true}},
            {"float", "1.5", %{"tag" => "float", "value" => 1.5}}
          ] do
        %{
          "id" => id,
          "surface" => "json.decode",
          "input" => %{"text" => text},
          "expect" => %{"status" => "valid", "output" => output}
        }
      end

    digest_bytes = Base.url_decode64!("e30", padding: false)
    tagged = :charter_revision_content |> Digest.hash(digest_bytes) |> Digest.to_tagged()

    digest_case = %{
      "id" => "digest-match",
      "surface" => "digest.hash",
      "input" => %{
        "domain" => "charter_revision_content",
        "bytes_base64url" => "e30",
        "tagged" => tagged
      },
      "expect" => %{"status" => "valid", "output" => %{}}
    }

    cases = json_cases ++ [digest_case]

    corpus = %Corpus{
      cases: cases,
      index: %{},
      index_bytes: "x",
      case_ids: MapSet.new(),
      identity: "x"
    }

    results = Runner.run(corpus)
    assert Enum.all?(results, & &1.agree)

    assert {:ok, bytes} = Report.to_bytes(corpus, results)

    assert bytes =~ "1.5"
  end

  test "digest cases execute the declared registered domain" do
    bytes = "terms"
    encoded = Base.url_encode64(bytes, padding: false)

    tagged =
      :legal_text
      |> Digest.hash(bytes)
      |> Digest.to_tagged()

    one = %{
      "id" => "legal-text-domain",
      "surface" => "digest.hash",
      "input" => %{
        "domain" => "legal_text",
        "bytes_base64url" => encoded,
        "tagged" => tagged
      },
      "expect" => %{"status" => "valid", "output" => %{}}
    }

    corpus = %Corpus{
      cases: [one],
      index: %{},
      index_bytes: "x",
      case_ids: MapSet.new(),
      identity: "x"
    }

    assert [%{agree: true}] = Runner.run(corpus)
  end

  test "the CLI requires an explicit corpus and verifies the certified shipped corpus" do
    assert ExUnit.CaptureIO.capture_io(:stderr, fn -> send(self(), {:exit, Cli.run([])}) end) =~
             "usage:"

    assert_received {:exit, 2}

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        send(self(), {:exit, Cli.run(["--corpus", "priv/conformance"])})
      end)

    assert output =~ ~s("agreement":true)
    assert_received {:exit, 0}
  end

  test "the CLI includes hidden corpus entries in the exact file-set check" do
    root = copy_shipped_corpus("hidden-entry")

    try do
      File.write!(Path.join(root, ".hidden-extra"), "not certified")

      assert ExUnit.CaptureIO.capture_io(:stderr, fn ->
               send(self(), {:exit, Cli.run(["--corpus", root])})
             end) =~ "conformance verification failed"

      assert_received {:exit, 1}
    after
      File.rm_rf!(Path.dirname(root))
    end
  end

  test "the CLI rejects non-regular corpus entries before attempting to read them" do
    root = copy_shipped_corpus("fifo-entry")
    fifo = Path.join(root, "blocking-fifo")

    try do
      {_output, 0} = System.cmd("mkfifo", [fifo])
      task = Task.async(fn -> Cli.run(["--corpus", root]) end)
      result = Task.yield(task, 1_000)
      if result == nil, do: Task.shutdown(task, :brutal_kill)

      assert result == {:ok, 1}
    after
      File.rm_rf!(Path.dirname(root))
    end
  end

  defp shipped_files do
    "priv/conformance/**/*"
    |> Path.wildcard()
    |> Enum.reject(&File.dir?/1)
    |> Map.new(fn path -> {Path.relative_to(path, "priv/conformance"), File.read!(path)} end)
  end

  defp copy_shipped_corpus(label) do
    scratch =
      Path.join(
        System.tmp_dir!(),
        "cap-cli-#{label}-#{System.unique_integer([:positive, :monotonic])}"
      )

    root = Path.join(scratch, "conformance")
    File.mkdir_p!(scratch)
    {:ok, _copied} = File.cp_r("priv/conformance", root)
    root
  end
end
