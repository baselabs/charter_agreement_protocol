defmodule CharterAgreementProtocol.Digest do
  @moduledoc """
  CAP never authorizes.

  Tagged SHA-256 content digests over canonical bytes.

  Preimages are `separator || <<0>> || bytes`; the wire form is
  `sha-256:<43-character unpadded base64url>`. Equality consumes every byte
  pair through an XOR accumulator and tests only once at the end.
  """

  alias CharterAgreementProtocol.{Base64Url, Error}

  @enforce_keys [:algorithm, :bytes]
  defstruct [:algorithm, :bytes]

  @type algorithm :: :sha256
  @type t :: %__MODULE__{algorithm: algorithm(), bytes: <<_::256>>}

  @tags %{sha256: "sha-256"}
  @sizes %{sha256: 32}
  @separators %{
    party_descriptor_content: "charter-agreement-protocol/party-descriptor-content",
    charter_revision_content: "charter-agreement-protocol/charter-revision-content",
    acceptance_content: "charter-agreement-protocol/acceptance-content",
    termination_content: "charter-agreement-protocol/termination-content",
    receipt_content: "charter-agreement-protocol/receipt-content",
    legal_text: "charter-agreement-protocol/legal-text",
    signature: "charter-agreement-protocol/signature",
    extension_schema: "charter-agreement-protocol/extension-schema",
    extension_registry: "charter-agreement-protocol/extension-registry",
    conformance_report: "charter-agreement-protocol/conformance-report",
    corpus_index: "charter-agreement-protocol/corpus-index",
    specification: "charter-agreement-protocol/specification"
  }

  @doc "Hash arbitrary iodata with SHA-256."
  @spec of(iodata()) :: t()
  def of(data), do: %__MODULE__{algorithm: :sha256, bytes: :crypto.hash(:sha256, data)}

  @doc "Hash bytes under a registered domain separator. Unknown domains raise."
  @spec hash(atom(), iodata()) :: t()
  def hash(domain, data), do: of([Map.fetch!(@separators, domain), <<0>>, data])

  @doc "Encode a fixed-width digest in tagged wire form."
  @spec to_tagged(t()) :: binary()
  def to_tagged(%__MODULE__{algorithm: algorithm, bytes: <<_::256>> = bytes}),
    do: Map.fetch!(@tags, algorithm) <> ":" <> Base64Url.encode(bytes)

  @doc "Parse a closed tagged digest string."
  @spec from_tagged(term()) :: {:ok, t()} | {:error, Error.t()}
  def from_tagged(input) when is_binary(input) do
    case String.split(input, ":", parts: 2) do
      [tag, body] ->
        with {:ok, algorithm} <- tag_lookup(tag),
             {:ok, bytes} <- body_lookup(algorithm, body) do
          {:ok, %__MODULE__{algorithm: algorithm, bytes: bytes}}
        end

      [_single] ->
        {:error, Error.new(:digest_encoding_invalid, ["digest"])}
    end
  end

  def from_tagged(_input), do: {:error, Error.new(:invalid_type, ["digest"])}

  @doc "Compare fixed-width digest bytes without an early content exit."
  @spec equal?(term(), term()) :: boolean()
  def equal?(%__MODULE__{algorithm: left_algorithm, bytes: left}, %__MODULE__{
        algorithm: right_algorithm,
        bytes: right
      }) do
    byte_size(left) == byte_size(right) and left_algorithm == right_algorithm and
      xor_zero?(left, right, 0)
  end

  def equal?(_left, _right), do: false

  @doc "Verify a tagged digest against bytes under a registered domain."
  @spec verify_content(atom(), binary(), term()) :: :ok | {:error, Error.t()}
  def verify_content(domain, bytes, tagged) when is_binary(bytes) do
    with {:ok, declared} <- from_tagged(tagged) do
      if equal?(hash(domain, bytes), declared),
        do: :ok,
        else: {:error, Error.new(:digest_mismatch, ["digest"])}
    end
  end

  def verify_content(_domain, _bytes, _tagged),
    do: {:error, Error.new(:invalid_type, ["digest"])}

  defp tag_lookup(tag) do
    case Enum.find(@tags, fn {_algorithm, spelling} -> spelling == tag end) do
      {algorithm, _spelling} -> {:ok, algorithm}
      nil -> {:error, Error.new(:digest_algorithm_unsupported, ["digest"])}
    end
  end

  defp body_lookup(algorithm, body) do
    expected_size = Map.fetch!(@sizes, algorithm)

    case Base64Url.decode(body) do
      {:ok, bytes} when byte_size(bytes) == expected_size ->
        {:ok, bytes}

      _error ->
        {:error, Error.new(:digest_encoding_invalid, ["digest"])}
    end
  end

  defp xor_zero?(<<left, left_rest::binary>>, <<right, right_rest::binary>>, accumulator),
    do:
      xor_zero?(
        left_rest,
        right_rest,
        Bitwise.bor(Bitwise.bxor(left, right), accumulator)
      )

  defp xor_zero?(<<>>, <<>>, accumulator), do: accumulator == 0
end
