defmodule CharterAgreementProtocol.Capability.Profile do
  @moduledoc """
  A capability profile: the `alg` names and `protocol_revision` values one
  deployment accepts. CAP never authorizes; a profile only narrows what
  verification admits.

  A profile is plain data, like `CharterAgreementProtocol.Limits`. The
  default, `full/0`, is every registry name and every accepted revision, so
  verifying without a profile is the same as verifying with the full one.
  Both axes apply to every signed artifact a verify call checks, including
  the context a standalone call verifies again: the revision and descriptor
  chain passed to `CharterAgreementProtocol.verify_acceptance/5` and
  `CharterAgreementProtocol.verify_termination/5`, and the chain view or bare
  revision passed to `CharterAgreementProtocol.verify_receipt/4`. A Charter
  Revision is unsigned, so only the revision axis applies to it.

  A profile does not constrain the keys a descriptor declares. Mixed key
  sets are legal, so a descriptor that declares ML-DSA keys but is signed
  with an Ed25519 key from its predecessor is in profile for an
  Ed25519-only deployment. To exclude ML-DSA-keyed descriptors, narrow the
  revision axis instead: ML-DSA keys are legal from `protocol_revision` 3,
  so `revisions: {1, 2}` excludes them.

  An artifact outside the profile fails before its own signature is
  checked, on every runtime alike, with `:algorithm_outside_profile` or
  `:revision_outside_profile`. A malformed profile fails with
  `:invalid_profile` before verification begins.

  ## Fields

  - `algorithms`: the accepted `alg` names, a non-empty list without
    duplicates.
  - `revisions`: the accepted `protocol_revision` range as `{min, max}`.

  ## Examples

      iex> {:ok, profile} = CharterAgreementProtocol.Capability.Profile.new(algorithms: ["Ed25519", "ML-DSA-65"])
      iex> CharterAgreementProtocol.Capability.Profile.admits?(profile, "Ed25519", 2)
      true
      iex> CharterAgreementProtocol.Capability.Profile.admits?(profile, "EdDSA", 1)
      false
      iex> CharterAgreementProtocol.Capability.Profile.new(revisions: {2, 9})
      {:error, %CharterAgreementProtocol.Error{code: :invalid_profile, subject: ["profile"], detail: nil}}
  """

  alias CharterAgreementProtocol.{Algorithm, Error}

  @enforce_keys [:algorithms, :revisions]
  defstruct [:algorithms, :revisions]

  @typedoc "An inclusive `{min, max}` range of protocol revisions."
  @type revision_range :: {pos_integer(), pos_integer()}
  @typedoc "One capability profile. See the module doc for each field."
  @type t :: %__MODULE__{
          algorithms: [binary()],
          revisions: revision_range()
        }

  @doc "The full profile: every registry name and every accepted revision."
  @spec full() :: t()
  def full do
    accepted = Algorithm.accepted_protocol_revisions()

    %__MODULE__{
      algorithms: Enum.map(Algorithm.registry(), & &1.name),
      revisions: {Enum.min(accepted), Enum.max(accepted)}
    }
  end

  @doc """
  Build a profile from options.

  - `:algorithms`: a non-empty list of registry `alg` names without
    duplicates. Omitted or `nil` means all.
  - `:revisions`: `{min, max}` with both values accepted revisions and
    `min <= max`. Omitted or `nil` means the full accepted range.

  Unknown options, unknown names and out-of-range bounds return
  `:invalid_profile`.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options \\ []) do
    if valid_options?(options) do
      full = full()

      algorithms =
        case Keyword.fetch(options, :algorithms) do
          {:ok, nil} -> full.algorithms
          {:ok, names} -> names
          :error -> full.algorithms
        end

      revisions =
        case Keyword.fetch(options, :revisions) do
          {:ok, nil} -> full.revisions
          {:ok, bounds} -> bounds
          :error -> full.revisions
        end

      {:ok, %__MODULE__{algorithms: algorithms, revisions: revisions}}
    else
      invalid()
    end
  end

  @doc "Whether a profile is complete and inside the registry."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{algorithms: algorithms, revisions: revisions}) do
    registry_names = Enum.map(Algorithm.registry(), & &1.name)
    accepted = Algorithm.accepted_protocol_revisions()

    is_list(algorithms) and algorithms != [] and algorithms == Enum.uniq(algorithms) and
      Enum.all?(algorithms, &(&1 in registry_names)) and valid_range?(revisions, accepted)
  end

  def valid?(_profile), do: false

  @doc """
  Whether one artifact's envelope `alg` and `protocol_revision` pair is
  inside the profile.
  """
  @spec admits?(t(), term(), term()) :: boolean()
  def admits?(%__MODULE__{} = profile, alg, protocol_revision)
      when is_binary(alg) and is_integer(protocol_revision) do
    {minimum, maximum} = profile.revisions

    alg in profile.algorithms and protocol_revision >= minimum and
      protocol_revision <= maximum
  end

  def admits?(_profile, _alg, _protocol_revision), do: false

  defp valid_range?({minimum, maximum}, accepted)
       when is_integer(minimum) and is_integer(maximum) do
    minimum in accepted and maximum in accepted and minimum <= maximum
  end

  defp valid_range?(_bounds, _accepted), do: false

  @doc false
  @spec check(term()) :: :ok | {:error, Error.t()}
  def check(value), do: if(valid?(value), do: :ok, else: invalid())

  defp valid_options?(options) when is_list(options) do
    if Keyword.keyword?(options) do
      keys = Keyword.keys(options)

      keys == Enum.uniq(keys) and Enum.all?(keys, &(&1 in [:algorithms, :revisions])) and
        valid_algorithms_option?(Keyword.get(options, :algorithms)) and
        valid_revisions_option?(Keyword.get(options, :revisions))
    else
      false
    end
  end

  defp valid_options?(_options), do: false

  defp valid_algorithms_option?(nil), do: true

  defp valid_algorithms_option?(names) do
    registry_names = Enum.map(Algorithm.registry(), & &1.name)

    is_list(names) and names != [] and names == Enum.uniq(names) and
      Enum.all?(names, &(&1 in registry_names))
  end

  defp valid_revisions_option?(nil), do: true

  defp valid_revisions_option?(bounds),
    do: valid_range?(bounds, Algorithm.accepted_protocol_revisions())

  defp invalid, do: {:error, Error.new(:invalid_profile, ["profile"])}
end
