defmodule CharterAgreementProtocol.Extension do
  @moduledoc """
  CAP never authorizes.

  Validates the one positional extension envelope against the compiled
  registry, artifact placement, lifecycle state, and digest-bound schemas.
  Unknown optional bodies remain in the artifact and are named as quarantined;
  no extension body enters a facts record.
  """

  alias CharterAgreementProtocol.{Canonicalization, Digest, Error, ExtensionRegistry, Schema}

  defmodule Outcome do
    @moduledoc """
    CAP never authorizes.

    Names-only extension disposition plus verbatim retained bodies; never a credential.
    """
    @enforce_keys [
      :critical_extensions,
      :optional_retained,
      :optional_quarantined,
      :retained_bodies
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            critical_extensions: [binary()],
            optional_retained: [binary()],
            optional_quarantined: [binary()],
            retained_bodies: [{binary(), CharterAgreementProtocol.Json.value()}]
          }
  end

  @namespace ~r/\A[a-z0-9][a-z0-9.-]*\/[a-z0-9][a-z0-9.-]*\z/
  @max_namespace_bytes 512
  @max_extensions 32
  @surfaces [:party_descriptor, :charter_revision, :receipt]

  @doc "Validate one extension envelope using the compiled schema set."
  @spec validate(term(), atom()) :: {:ok, Outcome.t()} | {:error, Error.t()}
  def validate(envelope, surface),
    do: validate(envelope, surface, ExtensionRegistry.schemas())

  @doc "Validate with an explicit schema view for digest-pinning and conformance probes."
  @spec validate(term(), atom(), map()) :: {:ok, Outcome.t()} | {:error, Error.t()}
  def validate(envelope, surface, schemas) when surface in @surfaces and is_map(schemas) do
    with {:ok, critical, optional} <- envelope(envelope),
         :ok <- namespaces(critical, optional),
         :ok <- cardinality(critical, optional),
         {:ok, critical_names} <- validate_critical(critical, surface, schemas),
         {:ok, retained, quarantined} <- validate_optional(optional, surface, schemas) do
      {:ok,
       %Outcome{
         critical_extensions: critical_names,
         optional_retained: Enum.map(retained, &elem(&1, 0)),
         optional_quarantined: quarantined,
         retained_bodies: retained
       }}
    end
  end

  def validate(_envelope, _surface, _schemas), do: error(:invalid_type, ["extensions"])

  defp envelope({:object, members}) when is_list(members) do
    case members do
      [{"critical", {:object, critical}}, {"optional", {:object, optional}}]
      when is_list(critical) and is_list(optional) ->
        {:ok, critical, optional}

      [{"optional", {:object, optional}}, {"critical", {:object, critical}}]
      when is_list(critical) and is_list(optional) ->
        {:ok, critical, optional}

      _other ->
        error(:unknown_member, ["extensions"])
    end
  end

  defp envelope(_value), do: error(:invalid_type, ["extensions"])

  defp namespaces(critical, optional) do
    names = Enum.map(critical ++ optional, &namespace_name/1)

    cond do
      Enum.any?(names, &is_nil/1) -> error(:extension_namespace_invalid)
      length(names) != length(Enum.uniq(names)) -> error(:extension_duplicate)
      true -> :ok
    end
  end

  defp namespace_name({name, _body}) when is_binary(name) do
    if byte_size(name) <= @max_namespace_bytes and Regex.match?(@namespace, name), do: name
  end

  defp namespace_name(_entry), do: nil

  defp cardinality(critical, optional) do
    if length(critical) + length(optional) <= @max_extensions,
      do: :ok,
      else: error(:cardinality_violation, ["extensions"])
  end

  defp validate_critical(entries, surface, schemas) do
    Enum.reduce_while(entries, {:ok, []}, fn {namespace, body}, {:ok, names} ->
      case critical_entry(namespace, body, surface, schemas) do
        :ok -> {:cont, {:ok, [namespace | names]}}
        {:error, %Error{}} = error -> {:halt, error}
      end
    end)
    |> reverse_names()
  end

  defp critical_entry(namespace, body, surface, schemas) do
    case ExtensionRegistry.entry(namespace) do
      :error ->
        error(:extension_unknown_critical)

      {:ok, %{state: :reserved}} ->
        error(:extension_unknown_critical)

      {:ok, %{state: :retired}} ->
        error(:extension_retired)

      {:ok, entry} ->
        with :ok <- criticality(entry, :critical),
             :ok <- placement(namespace, surface) do
          schema(entry, body, schemas)
        end
    end
  end

  defp validate_optional(entries, surface, schemas) do
    Enum.reduce_while(entries, {:ok, [], []}, fn {namespace, body},
                                                 {:ok, retained, quarantined} ->
      case optional_entry(namespace, body, surface, schemas) do
        :known -> {:cont, {:ok, [{namespace, body} | retained], quarantined}}
        :quarantined -> {:cont, {:ok, [{namespace, body} | retained], [namespace | quarantined]}}
        {:error, %Error{}} = error -> {:halt, error}
      end
    end)
    |> reverse_optional()
  end

  defp optional_entry(namespace, body, surface, schemas) do
    case ExtensionRegistry.entry(namespace) do
      :error ->
        :quarantined

      {:ok, %{state: state}} when state in [:reserved, :retired] ->
        :quarantined

      {:ok, entry} ->
        known_optional(entry, namespace, body, surface, schemas)
    end
  end

  defp known_optional(entry, namespace, body, surface, schemas) do
    with :ok <- criticality(entry, :optional),
         :ok <- placement(namespace, surface),
         :ok <- schema(entry, body, schemas) do
      :known
    end
  end

  defp criticality(%{criticality: expected}, expected), do: :ok
  defp criticality(_entry, _position), do: error(:extension_criticality_conflict)

  defp placement(namespace, surface) do
    case ExtensionRegistry.placement(namespace) do
      {:ok, ^surface} -> :ok
      _missing_or_other_surface -> error(:extension_scope_invalid)
    end
  end

  defp schema(%{schema_digest: nil}, _body, _schemas),
    do: error(:extension_schema_unavailable)

  defp schema(entry, body, schemas) do
    with {:ok, definition} <- fetch_schema(schemas, entry.namespace),
         :ok <- schema_digest(entry, definition),
         {:ok, _body} <- Schema.validate(definition, body) do
      :ok
    end
  end

  defp fetch_schema(schemas, namespace) do
    case Map.fetch(schemas, namespace) do
      {:ok, %Schema.Definition{} = definition} -> {:ok, definition}
      _missing -> error(:extension_schema_unavailable)
    end
  end

  defp schema_digest(entry, definition) do
    {:ok, bytes} = definition |> Schema.document() |> Canonicalization.encode()
    tagged = :extension_schema |> Digest.hash(bytes) |> Digest.to_tagged()

    if tagged == entry.schema_digest,
      do: :ok,
      else: error(:extension_schema_digest_mismatch)
  end

  defp reverse_names({:ok, names}), do: {:ok, Enum.reverse(names)}
  defp reverse_names({:error, %Error{}} = error), do: error

  defp reverse_optional({:ok, retained, quarantined}),
    do: {:ok, Enum.reverse(retained), Enum.reverse(quarantined)}

  defp reverse_optional({:error, %Error{}} = error), do: error

  defp error(code, subject \\ ["extensions"])
  defp error(:invalid_type, subject), do: {:error, Error.new(:invalid_type, subject)}
  defp error(:unknown_member, subject), do: {:error, Error.new(:unknown_member, subject)}

  defp error(:cardinality_violation, subject),
    do: {:error, Error.new(:cardinality_violation, subject)}

  defp error(:extension_namespace_invalid, subject),
    do: {:error, Error.new(:extension_namespace_invalid, subject)}

  defp error(:extension_duplicate, subject),
    do: {:error, Error.new(:extension_duplicate, subject)}

  defp error(:extension_unknown_critical, subject),
    do: {:error, Error.new(:extension_unknown_critical, subject)}

  defp error(:extension_criticality_conflict, subject),
    do: {:error, Error.new(:extension_criticality_conflict, subject)}

  defp error(:extension_retired, subject),
    do: {:error, Error.new(:extension_retired, subject)}

  defp error(:extension_schema_unavailable, subject),
    do: {:error, Error.new(:extension_schema_unavailable, subject)}

  defp error(:extension_schema_digest_mismatch, subject),
    do: {:error, Error.new(:extension_schema_digest_mismatch, subject)}

  defp error(:extension_scope_invalid, subject),
    do: {:error, Error.new(:extension_scope_invalid, subject)}
end
