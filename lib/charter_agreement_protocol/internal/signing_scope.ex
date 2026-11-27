defmodule CharterAgreementProtocol.Internal.SigningScope do
  @moduledoc false

  alias CharterAgreementProtocol.{Error, PartyDescriptor, Schema}

  @type t :: %{role: binary(), signers: [signer()]}
  @type signer :: %{key_thumbprint: binary(), artifact_kinds: [binary()]}
  @type status :: :not_required | :matched | :outside | :not_verified

  @kind_values Enum.map(~w(acceptance descriptor receipt termination), &{:string, &1})

  @signer Schema.definition("scope_signer", [
            Schema.field("key_thumbprint",
              required?: true,
              types: [:string],
              constraint: {:matches, ~r/\Asha-256:[A-Za-z0-9_-]{43}\z/}
            ),
            Schema.field("artifact_kinds", required?: true, types: [:array], cardinality: {0, 4})
          ])

  @role Schema.definition("signing_scope", [
          Schema.field("role",
            required?: true,
            types: [:string],
            constraint: {:string_bytes, 1, 128}
          ),
          Schema.field("signers",
            required?: true,
            types: [:array],
            cardinality: {0, 32},
            nested: {:array, @signer}
          )
        ])

  @spec field() :: Schema.Field.t()
  def field do
    Schema.field("signing_scopes", types: [:array], cardinality: {0, 64}, nested: {:array, @role})
  end

  @spec decode({:array, list()}, list()) :: {:ok, [t()]} | {:error, Error.t()}
  def decode({:array, entries}, active) do
    scopes = Enum.map(entries, &entry/1)

    if sorted_unique?(Enum.map(scopes, & &1.role)) and
         Enum.all?(scopes, &valid_signers?(&1.signers, active)) do
      {:ok,
       Enum.map(scopes, fn scope ->
         signers =
           Enum.map(scope.signers, fn signer ->
             %{signer | artifact_kinds: Enum.map(signer.artifact_kinds, &elem(&1, 1))}
           end)

         %{scope | signers: signers}
       end)}
    else
      {:error, Error.new(:descriptor_invalid, ["party_descriptor", "signing_scopes"])}
    end
  end

  defp entry({:object, members}) do
    %{"role" => {:string, role}, "signers" => {:array, signers}} = Map.new(members)
    %{role: role, signers: Enum.map(signers, &signer/1)}
  end

  defp signer({:object, members}) do
    %{"key_thumbprint" => {:string, thumbprint}, "artifact_kinds" => {:array, kinds}} =
      Map.new(members)

    %{key_thumbprint: thumbprint, artifact_kinds: kinds}
  end

  defp valid_signers?(signers, active) do
    sorted_unique?(Enum.map(signers, & &1.key_thumbprint)) and
      Enum.all?(signers, fn signer ->
        signer.key_thumbprint in active and sorted_unique?(signer.artifact_kinds) and
          Enum.all?(signer.artifact_kinds, &(&1 in @kind_values))
      end)
  end

  defp sorted_unique?(values), do: values == Enum.sort(Enum.uniq(values))

  @spec facts(map(), map(), binary() | nil, binary()) :: map()
  def facts(descriptor, key, role, kind) do
    {:ok, thumbprint} = PartyDescriptor.signer_thumbprint(key)

    %{
      scope_status: status(descriptor.signing_scopes, thumbprint, role, kind),
      signer_thumbprint: thumbprint
    }
  end

  defp status(nil, _thumbprint, _role, _kind), do: :not_required

  defp status(scopes, thumbprint, role, kind) do
    matched? =
      Enum.any?(scopes, fn scope ->
        (kind == "descriptor" or scope.role == role) and
          Enum.any?(
            scope.signers,
            &(&1.key_thumbprint == thumbprint and kind in &1.artifact_kinds)
          )
      end)

    if matched?, do: :matched, else: :outside
  end

  @spec for_key(map(), binary(), binary() | nil, binary()) :: map()
  def for_key(descriptor, kid, role, kind) do
    case Enum.find(descriptor.verification_keys, &(&1.key_id == kid and &1.status == :active)) do
      nil -> unverified()
      key -> facts(descriptor, key, role, kind)
    end
  end

  @spec in_chains(map(), list(), binary()) :: status()
  def in_chains(artifact, chains, kind) do
    descriptor =
      Enum.find_value(chains, fn chain ->
        Enum.find(chain.descriptors, &(&1.descriptor_digest == artifact.party_descriptor_digest))
      end)

    if descriptor do
      facts = for_key(descriptor.descriptor, artifact.envelope.kid, artifact.party_role, kind)
      facts.scope_status
    else
      :not_verified
    end
  end

  @spec unverified() :: %{scope_status: :not_verified, signer_thumbprint: nil}
  def unverified, do: %{scope_status: :not_verified, signer_thumbprint: nil}

  @spec refuse(status()) :: :ok | {:error, Error.t()}
  def refuse(:outside), do: {:error, Error.new(:signing_refused, ["signing_input", "scope"])}
  def refuse(_status), do: :ok
end
