defmodule CharterAgreementProtocol.Algorithm do
  @moduledoc """
  CAP never authorizes.

  The closed algorithm registry — one row per accepted JWS `alg` name.

  This table IS the algorithm registry `spec/evolution.md` describes as
  data-driven: a new algorithm lands by the same registry-and-revision act
  (a row here plus the key grammar its `key_algorithm` column requires),
  never by a parallel artifact family, media type, or header shape. Each
  row carries the accepted `alg` name, the minimum `protocol_revision` the
  name is legal at, the key algorithm it verifies with, and that key
  algorithm's exact public-key and signature byte lengths — the single
  source of truth the framing layer, key grammar, and producer seam all
  consult.

  For revisions 1–2 both classical rows verify with Ed25519 keys: RFC 9864's
  fully-specified `Ed25519` names exactly the RFC 8032
  EdDSA-with-Ed25519-key operation CAP already performs. Revision 3 admits
  ML-DSA (FIPS 204) under its RFC 9964 JOSE names — pure ML-DSA with the
  context fixed to the empty string — exercising the registry's second key
  grammar and second cryptographic primitive.

  ## The binding rule (per-artifact, not per-view)

  Decoding accepts `alg: "EdDSA"` at any accepted `protocol_revision`;
  `alg: "Ed25519"` requires `protocol_revision >= 2`; each `alg: "ML-DSA-*"`
  name requires `protocol_revision >= 3`; unknown revisions fail closed. An
  artifact carrying a name below its row's minimum is rejected — no honest
  producer could have minted the pair. Views mix revisions freely; the rule
  binds per artifact.

  ## Emission

  New minting is exactly the pairs (`"Ed25519"`, `protocol_revision` 2) and
  (`"ML-DSA-65"`, `protocol_revision` 3): the producer emits one of the
  fully-specified names at its emission revision. Old artifacts verify
  forever; nothing new mints a registry-deprecated identifier (RFC 9864
  marks `EdDSA` Deprecated, not Prohibited — see
  `docs/adr/algorithm-name-agility.md` and `docs/adr/ml-dsa-admission.md`).
  """

  alias CharterAgreementProtocol.{Canonicalization, Digest}

  @registry [
    %{
      name: "EdDSA",
      min_protocol_revision: 1,
      key_algorithm: "Ed25519",
      public_key_bytes: 32,
      signature_bytes: 64
    },
    %{
      name: "Ed25519",
      min_protocol_revision: 2,
      key_algorithm: "Ed25519",
      public_key_bytes: 32,
      signature_bytes: 64
    },
    %{
      name: "ML-DSA-44",
      min_protocol_revision: 3,
      key_algorithm: "ML-DSA-44",
      public_key_bytes: 1312,
      signature_bytes: 2420
    },
    %{
      name: "ML-DSA-65",
      min_protocol_revision: 3,
      key_algorithm: "ML-DSA-65",
      public_key_bytes: 1952,
      signature_bytes: 3309
    },
    %{
      name: "ML-DSA-87",
      min_protocol_revision: 3,
      key_algorithm: "ML-DSA-87",
      public_key_bytes: 2592,
      signature_bytes: 4627
    }
  ]

  @accepted_protocol_revisions [1, 2, 3]
  @emissions %{"Ed25519" => 2, "ML-DSA-65" => 3}

  @type row :: %{
          required(:name) => binary(),
          required(:min_protocol_revision) => pos_integer(),
          required(:key_algorithm) => binary(),
          required(:public_key_bytes) => pos_integer(),
          required(:signature_bytes) => pos_integer()
        }

  @doc "The closed registry (one row per accepted alg name)."
  @spec registry() :: [row()]
  def registry, do: @registry

  @doc "The accepted protocol_revision set (unknown revisions fail closed)."
  @spec accepted_protocol_revisions() :: [pos_integer()]
  def accepted_protocol_revisions, do: @accepted_protocol_revisions

  @doc """
  The closed mint set: each emission alg name paired with the exact
  protocol_revision its producer mints.
  """
  @spec emissions() :: %{binary() => pos_integer()}
  def emissions, do: @emissions

  @doc "The registry row for one alg name, or nil for unknown names."
  @spec row_for(term()) :: row() | nil
  def row_for(name) when is_binary(name), do: Enum.find(@registry, &(&1.name == name))
  def row_for(_name), do: nil

  @doc """
  Whether the (alg, protocol_revision) pair is legal on ONE artifact.

  The binding rule: the name must be a registry row, the revision must be
  accepted, and the revision must meet the row's minimum. Revision range
  alone is separately enforced by the per-artifact schemas; this check
  binds the name to the revision.
  """
  @spec binds?(term(), term()) :: boolean()
  def binds?(name, protocol_revision)
      when is_binary(name) and is_integer(protocol_revision) do
    case row_for(name) do
      %{min_protocol_revision: minimum} ->
        protocol_revision in @accepted_protocol_revisions and protocol_revision >= minimum

      nil ->
        false
    end
  end

  def binds?(_name, _protocol_revision), do: false

  @doc "Whether the name is a registry row (any revision)."
  @spec accepted_name?(term()) :: boolean()
  def accepted_name?(name) when is_binary(name), do: row_for(name) != nil
  def accepted_name?(_name), do: false

  @doc false
  @spec key_length(term()) :: non_neg_integer() | nil
  def key_length(key_algorithm) do
    case key_row_for(key_algorithm) do
      %{public_key_bytes: length} -> length
      nil -> nil
    end
  end

  @doc "The emission name producers use when the caller selects none."
  @spec default_emission_name() :: binary()
  def default_emission_name, do: "Ed25519"

  @doc """
  The domain-separated digest of every registry row.

  The signature algorithm registry's published identity: changes iff a row
  changes. The extension registry's digest (the manifest's historic
  `registry_digest` member) identifies extension profiles, not signature
  algorithms — this digest is the identity for the signature registry
  itself.
  """
  @spec registry_digest() :: Digest.t()
  def registry_digest do
    value =
      {:object,
       Enum.map(@registry, fn row ->
         {row.name,
          {:object,
           [
             {"name", {:string, row.name}},
             {"min_protocol_revision", {:integer, row.min_protocol_revision}},
             {"key_algorithm", {:string, row.key_algorithm}},
             {"public_key_bytes", {:integer, row.public_key_bytes}},
             {"signature_bytes", {:integer, row.signature_bytes}}
           ]}}
       end)}

    {:ok, bytes} = Canonicalization.encode(value)
    Digest.hash(:signature_registry, bytes)
  end

  @doc """
  The registry row for one key algorithm, or nil.

  The descriptor key grammar is written in key-algorithm terms: this lookup
  carries the exact public-key byte length each `algorithm` member value
  requires.
  """
  @spec key_row_for(term()) :: row() | nil
  def key_row_for(key_algorithm) when is_binary(key_algorithm),
    do: Enum.find(@registry, &(&1.key_algorithm == key_algorithm))

  def key_row_for(_key_algorithm), do: nil
end
