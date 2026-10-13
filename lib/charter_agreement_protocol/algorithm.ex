defmodule CharterAgreementProtocol.Algorithm do
  @moduledoc """
  The signature algorithm registry: one row per accepted JWS `alg` name.
  CAP never authorizes; the registry only says which signatures it can
  check.

  Each row gives the `alg` name, the lowest `protocol_revision` that may use
  it, the key algorithm it verifies with, and that key algorithm's exact
  public-key and signature lengths in bytes. Framing, the descriptor key
  grammar and the signing-input builders all read this one table. A new
  algorithm is added as a new row (plus the key grammar it needs), never as a
  new artifact family, media type or header shape. `spec/evolution.md`
  describes that process.

  | `alg` | Lowest `protocol_revision` | Key algorithm | Public key bytes | Signature bytes |
  |---|---:|---|---:|---:|
  | `EdDSA` | 1 | Ed25519 | 32 | 64 |
  | `Ed25519` | 2 | Ed25519 | 32 | 64 |
  | `ML-DSA-44` | 3 | ML-DSA-44 | 1312 | 2420 |
  | `ML-DSA-65` | 3 | ML-DSA-65 | 1952 | 3309 |
  | `ML-DSA-87` | 3 | ML-DSA-87 | 2592 | 4627 |

  `EdDSA` and `Ed25519` name the same operation: RFC 9864's fully specified
  `Ed25519` is exactly the RFC 8032 EdDSA-with-Ed25519 check CAP already
  performs. Revision 3 adds ML-DSA (FIPS 204) under its JOSE names, as pure
  ML-DSA with an empty context string.

  ## Which name is legal at which revision

  The rule binds each artifact on its own. `EdDSA` is accepted at every
  accepted `protocol_revision`, `Ed25519` needs revision 2 or later, and
  each `ML-DSA-*` name needs revision 3 or later. An artifact with a name
  below its row's minimum is rejected, and unknown revisions fail closed. A
  set may mix revisions freely.

  ## What producers emit

  New artifacts use exactly one of two pairs: `"Ed25519"` at
  `protocol_revision` 2 (the default) or `"ML-DSA-65"` at
  `protocol_revision` 3. Older artifacts keep verifying. Nothing new is
  minted under `EdDSA`, which RFC 9864 marks deprecated. The
  [algorithm name ADR](algorithm-name-agility.md) and the
  [ML-DSA ADR](ml-dsa-admission.md) record why.

  ## Examples

      iex> CharterAgreementProtocol.Algorithm.emissions()
      %{"Ed25519" => 2, "ML-DSA-65" => 3}
      iex> CharterAgreementProtocol.Algorithm.binds?("Ed25519", 1)
      false
      iex> CharterAgreementProtocol.Algorithm.row_for("ML-DSA-65").signature_bytes
      3309
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

  @typedoc "One registry row."
  @type row :: %{
          required(:name) => binary(),
          required(:min_protocol_revision) => pos_integer(),
          required(:key_algorithm) => binary(),
          required(:public_key_bytes) => pos_integer(),
          required(:signature_bytes) => pos_integer()
        }

  @doc "Every registry row, one per accepted `alg` name."
  @spec registry() :: [row()]
  def registry, do: @registry

  @doc "Every accepted `protocol_revision`. Any other revision fails closed."
  @spec accepted_protocol_revisions() :: [pos_integer()]
  def accepted_protocol_revisions, do: @accepted_protocol_revisions

  @doc """
  The two `alg` names producers emit, each with the exact
  `protocol_revision` its claims must carry.
  """
  @spec emissions() :: %{binary() => pos_integer()}
  def emissions, do: @emissions

  @doc "The registry row for one `alg` name, or `nil` for an unknown name."
  @spec row_for(term()) :: row() | nil
  def row_for(name) when is_binary(name), do: Enum.find(@registry, &(&1.name == name))
  def row_for(_name), do: nil

  @doc """
  Whether an `alg` name and `protocol_revision` are legal together on one
  artifact.

  The name must be a registry row, the revision must be accepted, and the
  revision must be at least the row's minimum. The artifact schemas check
  the revision range on their own; this check ties the name to the
  revision.
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

  @doc "Whether a name is a registry row, at any revision."
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

  @doc "The `alg` name producers use when the caller names none: `\"Ed25519\"`."
  @spec default_emission_name() :: binary()
  def default_emission_name, do: "Ed25519"

  @doc """
  The digest of every registry row.

  This identifies the signature algorithm registry: it changes exactly when
  a row changes. It is a different value from the extension registry digest
  (the release manifest's `registry_digest` member), which identifies
  extension profiles.
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
  The registry row for one key algorithm, or `nil`.

  Descriptor keys name a key algorithm in their `algorithm` member. This
  lookup gives the exact public-key length that value requires.
  """
  @spec key_row_for(term()) :: row() | nil
  def key_row_for(key_algorithm) when is_binary(key_algorithm),
    do: Enum.find(@registry, &(&1.key_algorithm == key_algorithm))

  def key_row_for(_key_algorithm), do: nil
end
