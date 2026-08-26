defmodule CharterAgreementProtocol.Algorithm do
  @moduledoc """
  CAP never authorizes.

  The closed algorithm registry — one row per accepted JWS `alg` name.

  This table IS the algorithm registry `spec/evolution.md` describes as
  data-driven: a new algorithm lands by the same registry-and-revision act
  (a row here plus the key grammar its `key_algorithm` column requires),
  never by a parallel artifact family, media type, or header shape. Each
  row carries the accepted `alg` name, the minimum `protocol_revision` the
  name is legal at, and the key algorithm it verifies with.

  For revisions 1–2 both rows verify with Ed25519 keys: RFC 9864's
  fully-specified `Ed25519` names exactly the RFC 8032
  EdDSA-with-Ed25519-key operation CAP already performs — the two names
  are one cryptographic operation with two spellings, which is why the
  registry adds a name here without touching the key grammar or the
  verification path.

  ## The binding rule (per-artifact, not per-view)

  Decoding accepts `alg: "EdDSA"` at any accepted `protocol_revision`;
  `alg: "Ed25519"` requires `protocol_revision >= 2`; unknown revisions
  fail closed. An artifact carrying `Ed25519` at revision 1 is rejected —
  no honest producer could have minted it (revision 1 closed the header
  to `EdDSA`). Views mix revisions freely; the rule binds per artifact.

  ## Emission

  New minting is exactly (`"Ed25519"`, `protocol_revision` 2): the
  signing-input producer emits the fully-specified name at the current
  revision. Old artifacts verify forever; nothing new mints a
  registry-deprecated identifier (RFC 9864 marks `EdDSA` Deprecated, not
  Prohibited — see `docs/adr/algorithm-name-agility.md`).
  """

  @registry [
    %{
      name: "EdDSA",
      min_protocol_revision: 1,
      key_algorithm: "Ed25519"
    },
    %{
      name: "Ed25519",
      min_protocol_revision: 2,
      key_algorithm: "Ed25519"
    }
  ]

  @accepted_protocol_revisions [1, 2]
  @emission_name "Ed25519"
  @emission_protocol_revision 2

  @type row :: %{
          required(:name) => binary(),
          required(:min_protocol_revision) => pos_integer(),
          required(:key_algorithm) => binary()
        }

  @doc "The closed registry (one row per accepted alg name)."
  @spec registry() :: [row()]
  def registry, do: @registry

  @doc "The accepted protocol_revision set (unknown revisions fail closed)."
  @spec accepted_protocol_revisions() :: [pos_integer()]
  def accepted_protocol_revisions, do: @accepted_protocol_revisions

  @doc "The alg name every newly minted artifact carries."
  @spec emission_name() :: binary()
  def emission_name, do: @emission_name

  @doc "The protocol_revision every newly minted artifact carries."
  @spec emission_protocol_revision() :: pos_integer()
  def emission_protocol_revision, do: @emission_protocol_revision

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
    case Enum.find(@registry, &(&1.name == name)) do
      %{min_protocol_revision: minimum} ->
        protocol_revision in @accepted_protocol_revisions and protocol_revision >= minimum

      nil ->
        false
    end
  end

  def binds?(_name, _protocol_revision), do: false

  @doc "Whether the name is a registry row (any revision)."
  @spec accepted_name?(term()) :: boolean()
  def accepted_name?(name) when is_binary(name), do: Enum.any?(@registry, &(&1.name == name))
  def accepted_name?(_name), do: false
end
