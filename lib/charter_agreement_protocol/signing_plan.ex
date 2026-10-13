defmodule CharterAgreementProtocol.SigningPlan do
  @moduledoc """
  A checked input for external signing. CAP never authorizes and never signs.

  Sign `signing_input.message`, then pass this record and the raw signature
  to `CharterAgreementProtocol.finish_signing/2`. `key` is `:matched` when
  the snapshot matches a resolved descriptor key, or `:unnamed` for a
  receipt checked against a bare revision.

  `public_key`, `verify_with`, `limits` and `profile` are internal fields.
  Callers must retain the returned record without changing these fields.
  """

  alias CharterAgreementProtocol, as: CAP

  alias CharterAgreementProtocol.{
    Acceptance,
    Algorithm,
    ArtifactSet,
    Capability,
    Capability.Profile,
    Chain,
    ChainFacts,
    CharterRevision,
    DescriptorFacts,
    Error,
    Internal.Retained,
    Limits,
    PartyDescriptor,
    Receipt,
    Signature,
    SigningInput,
    TerminationNotice
  }

  @enforce_keys [:signing_input, :key, :public_key, :verify_with, :limits, :profile]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          signing_input: SigningInput.t(),
          key: :matched | :unnamed,
          public_key: binary(),
          verify_with:
            nil
            | DescriptorFacts.t()
            | {CharterRevision.t(), CharterAgreementProtocol.DescriptorChain.t()}
            | ChainFacts.t()
            | CharterRevision.t(),
          limits: Limits.t(),
          profile: Profile.t()
        }

  @doc false
  @spec prepare(term(), term(), term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def prepare(kind, input, context, limits, profile) do
    with :ok <- options(limits, profile),
         :ok <- context_type(kind, context),
         {:ok, signing_input, artifact, public_key} <- build(kind, input, limits),
         :ok <- key_shape(public_key, signing_input.alg),
         {:ok, verify_with} <- derive(kind, artifact, context, limits, profile),
         {:ok, provisional} <-
           Retained.compact(artifact.envelope),
         {:ok, prepared} <- prepare_artifact(kind, provisional, verify_with, limits, profile),
         {:ok, key} <- membership(prepared.keys, public_key, signing_input.alg),
         :ok <- supported(signing_input.alg) do
      {:ok,
       %__MODULE__{
         signing_input: signing_input,
         key: key,
         public_key: public_key,
         verify_with: prepared.verify_with,
         limits: limits,
         profile: profile
       }}
    end
  end

  @doc false
  @spec finish(term(), term()) :: {:ok, binary()} | {:error, Error.t()}
  def finish(
        %__MODULE__{signing_input: %SigningInput{} = input, limits: _, profile: _, verify_with: _} =
          plan,
        signature
      ) do
    with :ok <- options(plan.limits, plan.profile),
         {:ok, compact} <- SigningInput.assemble_under(input, signature, plan.limits),
         {:ok, _facts} <- verify(input.kind, compact, plan.verify_with, plan.limits, plan.profile) do
      {:ok, compact}
    end
  end

  def finish(_plan, _signature), do: invalid_type()

  defp options(limits, profile) do
    cond do
      not Limits.valid?(limits) -> {:error, Error.new(:invalid_limits, ["limits"])}
      not Profile.valid?(profile) -> {:error, Error.new(:invalid_profile, ["profile"])}
      true -> :ok
    end
  end

  defp context_type(:party_descriptor, nil), do: :ok
  defp context_type(:party_descriptor, %DescriptorFacts{}), do: :ok
  defp context_type(kind, %ArtifactSet{}) when kind in [:acceptance, :termination], do: :ok
  defp context_type(:receipt, %ChainFacts{}), do: :ok
  defp context_type(:receipt, %CharterRevision{}), do: :ok
  defp context_type(_kind, _context), do: invalid_type()

  defp build(kind, %{"public_key" => public_key} = input, limits) do
    with {:ok, signing_input, artifact} <-
           SigningInput.build(kind, Map.delete(input, "public_key"), limits) do
      {:ok, signing_input, artifact, public_key}
    end
  end

  defp build(_kind, _input, _limits),
    do: {:error, Error.new(:signing_input_invalid, ["signing_input"])}

  defp key_shape(public_key, alg) do
    if Signature.valid_key?(public_key, alg),
      do: :ok,
      else: {:error, Error.new(:signing_key_invalid, ["signing_input", "public_key"])}
  end

  defp derive(kind, artifact, set, limits, _profile) when kind in [:acceptance, :termination] do
    with {:ok, chain} <-
           Chain.verify(
             set.revisions,
             set.acceptances,
             set.descriptors,
             set.terminations,
             limits,
             Profile.full()
           ),
         {:ok, _revision} <- SigningInput.refusal_check(kind, artifact, chain) do
      Chain.signing_context(kind, artifact, chain)
    end
  end

  defp derive(_kind, _artifact, context, _limits, _profile), do: {:ok, context}

  defp prepare_artifact(:party_descriptor, compact, context, limits, profile),
    do: PartyDescriptor.prepare(compact, context, limits, profile)

  defp prepare_artifact(:receipt, compact, context, limits, profile),
    do: Receipt.prepare(compact, context, limits, profile)

  defp prepare_artifact(:acceptance, compact, {revision, chain}, limits, profile),
    do: Acceptance.prepare(compact, revision, chain, limits, profile)

  defp prepare_artifact(:termination, compact, {revision, chain}, limits, profile),
    do: TerminationNotice.prepare(compact, revision, chain, limits, profile)

  defp membership(:unnamed, _public_key, _alg), do: {:ok, :unnamed}

  defp membership(keys, public_key, alg) do
    %{key_algorithm: key_algorithm} = Algorithm.row_for(alg)

    if Enum.any?(keys, &(candidate(&1) == {public_key, key_algorithm})),
      do: {:ok, :matched},
      else: {:error, Error.new(:signing_key_mismatch, ["signing_input", "public_key"])}
  end

  defp candidate({public_key, algorithm}), do: {public_key, algorithm}
  defp candidate(key), do: {key.public_key, key.algorithm}

  defp supported(alg) do
    %{key_algorithm: algorithm} = Algorithm.row_for(alg)

    if Capability.kat_verifies?(algorithm),
      do: :ok,
      else: {:error, Error.new(:algorithm_unsupported_on_substrate, ["signature", algorithm])}
  end

  defp verify(:party_descriptor, compact, context, limits, profile),
    do: CAP.verify_descriptor(compact, context, limits, profile)

  defp verify(:receipt, compact, context, limits, profile),
    do: CAP.verify_receipt(compact, context, limits, profile)

  defp verify(:acceptance, compact, {revision, chain}, limits, profile),
    do: CAP.verify_acceptance(compact, revision, chain, limits, profile)

  defp verify(:termination, compact, {revision, chain}, limits, profile),
    do: CAP.verify_termination(compact, revision, chain, limits, profile)

  defp verify(_kind, _compact, _context, _limits, _profile), do: invalid_type()

  defp invalid_type, do: {:error, Error.new(:invalid_type, ["signing_plan"])}
end
