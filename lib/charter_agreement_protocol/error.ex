defmodule CharterAgreementProtocol.Error do
  @moduledoc """
  The typed error CAP's decode, verify and producer functions return on
  failure. CAP never authorizes; an error says why bytes were rejected,
  nothing more. A few low-level helpers raise on misuse instead, and their
  docs say so: `CharterAgreementProtocol.Digest.hash/2` with an unknown
  domain, and `new/3` itself with an undeclared code.

  Failures are `{:error, %CharterAgreementProtocol.Error{}}` with three
  fields:

  - `code`: an atom from the closed list in `codes/0`. Match on this.
  - `subject`: a path of protocol-owned names, such as
    `["compact_jws", "signature"]`. It never contains your input.
  - `detail`: `nil`, or a protocol-owned atom or string.

  Errors CAP returns never echo rejected bytes, so they are safe to log.
  `new/3` does not check where its strings come from, so an error you build
  yourself carries whatever subject and detail you give it. The
  [Handle errors](error-codes.md) guide gives each code's meaning, cause and
  what to do.

  ## Codes by layer

  - Encoding and JSON: `:base64url_invalid`, `:base64url_padded`,
    `:invalid_syntax`, `:invalid_encoding`, `:invalid_number`,
    `:number_not_double_expressible`, `:duplicate_member`,
    `:trailing_bytes`, `:non_canonical_bytes`, `:integer_magnitude`,
    `:timestamp_invalid`.
  - Digests: `:digest_algorithm_unsupported`, `:digest_encoding_invalid`,
    `:digest_mismatch`.
  - Caller input: `:invalid_type`, `:invalid_limits`, `:invalid_profile`,
    `:limit_exceeded`.
  - Profiles and runtime: `:algorithm_outside_profile`,
    `:revision_outside_profile`, `:algorithm_unsupported_on_substrate`.
  - Schemas: `:unknown_member`, `:missing_required`,
    `:constraint_violation`, `:cardinality_violation`, `:nested_invalid`,
    `:cross_field_invalid`.
  - Envelopes and signatures: `:compact_invalid`,
    `:protected_header_invalid`, `:signature_invalid`.
  - Artifacts: `:descriptor_invalid`, `:descriptor_key_invalid`,
    `:descriptor_chain_invalid`, `:revision_invalid`, `:acceptance_invalid`,
    `:acceptance_claims_mismatch`, `:acceptance_equivocation_invalid`,
    `:termination_invalid`, `:termination_claims_mismatch`,
    `:chain_invalid`, `:governing_invalid`, `:receipt_invalid`,
    `:receipt_claims_mismatch`.
  - Extensions: `:extension_namespace_invalid`, `:extension_duplicate`,
    `:extension_unknown_critical`, `:extension_criticality_conflict`,
    `:extension_retired`, `:extension_schema_unavailable`,
    `:extension_schema_digest_mismatch`, `:extension_scope_invalid`.
  - Producing: `:signing_input_invalid`, `:signing_refused`,
    `:signing_key_invalid`, `:signing_key_mismatch`.
  - Conformance corpus: `:corpus_index_invalid`, `:corpus_case_invalid`,
    `:corpus_hash_mismatch`, `:corpus_file_set_mismatch`,
    `:corpus_case_id_duplicate`, `:corpus_count_mismatch`,
    `:corpus_applicability_incomplete`, `:corpus_empty`.

  `:algorithm_unsupported_on_substrate` means this runtime cannot verify the
  artifact's algorithm, so the signature was not checked. It is a fact about
  your runtime, not a verdict on the bytes: treat the artifact as neither
  valid nor invalid. See `CharterAgreementProtocol.capabilities/0`.

  ## Examples

      iex> CharterAgreementProtocol.Base64Url.decode("AQID=")
      {:error, %CharterAgreementProtocol.Error{code: :base64url_padded, subject: ["base64url"], detail: nil}}
      iex> CharterAgreementProtocol.Error.declared?(:base64url_padded)
      true
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
    :invalid_profile,
    :algorithm_outside_profile,
    :revision_outside_profile,
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
    :algorithm_unsupported_on_substrate,
    :descriptor_invalid,
    :descriptor_key_invalid,
    :descriptor_chain_invalid,
    :revision_invalid,
    :acceptance_invalid,
    :acceptance_claims_mismatch,
    :acceptance_equivocation_invalid,
    :termination_invalid,
    :termination_claims_mismatch,
    :chain_invalid,
    :governing_invalid,
    :receipt_invalid,
    :receipt_claims_mismatch,
    :extension_namespace_invalid,
    :extension_duplicate,
    :extension_unknown_critical,
    :extension_criticality_conflict,
    :extension_retired,
    :extension_schema_unavailable,
    :extension_schema_digest_mismatch,
    :extension_scope_invalid,
    :signing_input_invalid,
    :signing_refused,
    :signing_key_invalid,
    :signing_key_mismatch
  ]

  @typedoc "One code from `codes/0`."
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
          | :invalid_profile
          | :algorithm_outside_profile
          | :revision_outside_profile
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
          | :algorithm_unsupported_on_substrate
          | :descriptor_invalid
          | :descriptor_key_invalid
          | :descriptor_chain_invalid
          | :revision_invalid
          | :acceptance_invalid
          | :acceptance_claims_mismatch
          | :acceptance_equivocation_invalid
          | :termination_invalid
          | :termination_claims_mismatch
          | :chain_invalid
          | :governing_invalid
          | :receipt_invalid
          | :receipt_claims_mismatch
          | :extension_namespace_invalid
          | :extension_duplicate
          | :extension_unknown_critical
          | :extension_criticality_conflict
          | :extension_retired
          | :extension_schema_unavailable
          | :extension_schema_digest_mismatch
          | :extension_scope_invalid
          | :signing_input_invalid
          | :signing_refused
          | :signing_key_invalid
          | :signing_key_mismatch
  @typedoc "A path of protocol-owned names and indexes. Never caller input."
  @type subject :: [binary() | non_neg_integer()]
  @typedoc "An optional protocol-owned atom or string."
  @type detail :: nil | atom() | binary()
  @typedoc "A typed, value-free failure."
  @type t :: %__MODULE__{code: code(), subject: subject(), detail: detail()}

  @doc "Every error code CAP can return."
  @spec codes() :: [code()]
  def codes, do: @codes

  @doc "Whether a value is a declared error code."
  @spec declared?(term()) :: boolean()
  def declared?(code), do: code in @codes

  @doc """
  Build an error. Raises `ArgumentError` for an unknown code, a subject that
  is not a list of strings and non-negative integers, or a detail that is
  not `nil`, an atom or a string.
  """
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
