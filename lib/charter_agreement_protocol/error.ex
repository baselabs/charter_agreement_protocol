defmodule CharterAgreementProtocol.Error do
  @moduledoc """
  Value-free typed failure returned by the protocol codecs.

  `subject` is built from protocol-owned names, never from rejected input.
  The implemented code vocabulary is closed and architecture-gated in both
  directions: an undeclared emission and a declared-but-unemitted code both
  fail the build.
  """

  @enforce_keys [:code, :subject]
  defstruct [:code, :subject, :detail]

  @codes [
    :base64url_invalid,
    :base64url_padded,
    :invalid_syntax,
    :invalid_encoding,
    :invalid_number,
    :number_not_double_expressible,
    :duplicate_member,
    :trailing_bytes,
    :invalid_type,
    :non_canonical_bytes,
    :integer_magnitude,
    :digest_algorithm_unsupported,
    :digest_encoding_invalid,
    :digest_mismatch,
    :invalid_limits,
    :limit_exceeded,
    :unknown_member,
    :missing_required,
    :constraint_violation,
    :cardinality_violation,
    :nested_invalid,
    :cross_field_invalid,
    :corpus_index_invalid,
    :corpus_case_invalid,
    :corpus_hash_mismatch,
    :corpus_file_set_mismatch,
    :corpus_case_id_duplicate,
    :corpus_count_mismatch,
    :corpus_applicability_incomplete,
    :corpus_empty,
    :timestamp_invalid,
    :compact_invalid,
    :protected_header_invalid,
    :signature_invalid,
    :descriptor_invalid,
    :descriptor_key_invalid,
    :descriptor_chain_invalid,
    :revision_invalid,
    :acceptance_invalid,
    :acceptance_claims_mismatch,
    :acceptance_equivocation_invalid
  ]

  @type code ::
          :base64url_invalid
          | :base64url_padded
          | :invalid_syntax
          | :invalid_encoding
          | :invalid_number
          | :number_not_double_expressible
          | :duplicate_member
          | :trailing_bytes
          | :invalid_type
          | :non_canonical_bytes
          | :integer_magnitude
          | :digest_algorithm_unsupported
          | :digest_encoding_invalid
          | :digest_mismatch
          | :invalid_limits
          | :limit_exceeded
          | :unknown_member
          | :missing_required
          | :constraint_violation
          | :cardinality_violation
          | :nested_invalid
          | :cross_field_invalid
          | :corpus_index_invalid
          | :corpus_case_invalid
          | :corpus_hash_mismatch
          | :corpus_file_set_mismatch
          | :corpus_case_id_duplicate
          | :corpus_count_mismatch
          | :corpus_applicability_incomplete
          | :corpus_empty
          | :timestamp_invalid
          | :compact_invalid
          | :protected_header_invalid
          | :signature_invalid
          | :descriptor_invalid
          | :descriptor_key_invalid
          | :descriptor_chain_invalid
          | :revision_invalid
          | :acceptance_invalid
          | :acceptance_claims_mismatch
          | :acceptance_equivocation_invalid
  @type subject :: [binary() | non_neg_integer()]
  @type detail :: nil | atom() | binary()
  @type t :: %__MODULE__{code: code(), subject: subject(), detail: detail()}

  @doc "The complete implemented error-code vocabulary."
  @spec codes() :: [code()]
  def codes, do: @codes

  @doc "Whether a value is a declared error code."
  @spec declared?(term()) :: boolean()
  def declared?(code), do: code in @codes

  @doc "Construct a declared value-free error. Unknown codes fail loudly."
  @spec new(code(), subject(), detail()) :: t()
  def new(code, subject \\ [], detail \\ nil) do
    if declared?(code) and valid_subject?(subject) and valid_detail?(detail) do
      %__MODULE__{code: code, subject: subject, detail: detail}
    else
      raise ArgumentError, "undeclared error code, invalid subject, or invalid detail"
    end
  end

  defp valid_subject?(subject) when is_list(subject),
    do: Enum.all?(subject, &(is_binary(&1) or (is_integer(&1) and &1 >= 0)))

  defp valid_subject?(_subject), do: false

  defp valid_detail?(detail), do: is_nil(detail) or is_atom(detail) or is_binary(detail)
end
