defmodule CharterAgreementProtocol.Conformance.Report do
  @moduledoc """
  CAP never authorizes.

  Canonical, corpus-identity-bound conformance report. Agreement requires the
  complete projected result of every case to match its certified expectation.
  """

  alias CharterAgreementProtocol.{Base64Url, Canonicalization, Digest}
  alias CharterAgreementProtocol.Conformance.Corpus

  @format "charter-agreement-protocol-conformance-report"

  @enforce_keys [:agreement, :exit_status, :total, :agreed, :disagreed]
  defstruct [:agreement, :exit_status, :total, :agreed, :disagreed]

  @type t :: %__MODULE__{
          agreement: boolean(),
          exit_status: 0 | 1,
          total: non_neg_integer(),
          agreed: non_neg_integer(),
          disagreed: non_neg_integer()
        }

  @doc "Summarize complete case agreement."
  @spec build(Corpus.t(), [map()]) :: t()
  def build(%Corpus{cases: cases}, results) when length(cases) == length(results) do
    agreed = Enum.count(results, & &1.agree)
    total = length(results)
    agreement = agreed == total and total > 0

    %__MODULE__{
      agreement: agreement,
      exit_status: if(agreement, do: 0, else: 1),
      total: total,
      agreed: agreed,
      disagreed: total - agreed
    }
  end

  @doc "Encode the complete report as canonical JSON bytes."
  @spec to_bytes(Corpus.t(), [map()]) :: {:ok, binary()}
  def to_bytes(%Corpus{} = corpus, results) do
    summary = build(corpus, results)

    document = %{
      "format" => @format,
      "agreement" => summary.agreement,
      "exit_status" => summary.exit_status,
      "total" => summary.total,
      "agreed" => summary.agreed,
      "disagreed" => summary.disagreed,
      "corpus_digest" => corpus.identity,
      "registry_digest" => corpus.index["registry_digest"],
      "index_sha256_base64url" => index_identity(corpus.index_bytes),
      "results" => Enum.map(results, &result_document/1)
    }

    Canonicalization.encode(tagged(document))
  end

  @doc "Return the raw SHA-256 identity of exact canonical index bytes."
  @spec index_identity(binary()) :: binary()
  def index_identity(bytes) when is_binary(bytes),
    do: bytes |> Digest.of() |> Map.fetch!(:bytes) |> Base64Url.encode()

  defp result_document(result) do
    %{
      "id" => result.id,
      "surface" => result.surface,
      "agree" => result.agree,
      "expected" => result.expected,
      "actual" => result.actual
    }
  end

  defp tagged(nil), do: :null
  defp tagged(value) when is_boolean(value), do: {:boolean, value}
  defp tagged(value) when is_integer(value), do: {:integer, value}
  defp tagged(value) when is_float(value), do: {:float, value}
  defp tagged(value) when is_binary(value), do: {:string, value}
  defp tagged(value) when is_list(value), do: {:array, Enum.map(value, &tagged/1)}

  defp tagged(value) when is_map(value),
    do: {:object, Enum.map(value, fn {key, item} -> {key, tagged(item)} end)}
end
