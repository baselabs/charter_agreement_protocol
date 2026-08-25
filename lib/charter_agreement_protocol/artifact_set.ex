defmodule CharterAgreementProtocol.ArtifactSet do
  @moduledoc "Raw caller-supplied artifacts retained for pure set-level verification."

  alias CharterAgreementProtocol.Error

  @enforce_keys [:revisions, :acceptances, :terminations, :descriptors]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          revisions: [binary()],
          acceptances: [binary()],
          terminations: [binary()],
          descriptors: [binary()]
        }

  @doc "Build a typed raw artifact set without verifying or reordering it."
  @spec build(term(), term(), term(), term()) :: {:ok, t()} | {:error, Error.t()}
  def build(revisions, acceptances, terminations, descriptors)
      when is_list(revisions) and is_list(acceptances) and is_list(terminations) and
             is_list(descriptors) do
    if Enum.all?(revisions ++ acceptances ++ terminations ++ descriptors, &is_binary/1) do
      {:ok,
       %__MODULE__{
         revisions: revisions,
         acceptances: acceptances,
         terminations: terminations,
         descriptors: descriptors
       }}
    else
      invalid()
    end
  end

  def build(_revisions, _acceptances, _terminations, _descriptors), do: invalid()

  defp invalid, do: {:error, Error.new(:invalid_type, ["artifact_set"])}
end

defimpl Inspect, for: CharterAgreementProtocol.ArtifactSet do
  def inspect(_value, _options),
    do: Inspect.Algebra.string("#CharterAgreementProtocol.ArtifactSet<redacted>")
end
