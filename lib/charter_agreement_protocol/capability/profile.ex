defmodule CharterAgreementProtocol.Capability.Profile do
  @moduledoc """
  CAP never authorizes.

  Caller-supplied capability profile: the subset of registry `alg` names and
  `protocol_revision` values one deployment verifies.

  Pure data like `Limits`: no environment or application config is consulted.
  The default (`full/0`) is the whole registry and every accepted revision,
  so verification without a profile is exactly verification with the full
  profile. Two axes, applied per artifact (acceptances and terminations
  included): the accepted envelope `alg` names, and the accepted
  `protocol_revision` range.

  A profile deliberately does NOT constrain the key material a descriptor
  declares: mixed-algorithm key sets are legal, and a descriptor declaring
  ML-DSA keys that is Ed25519-signed by a predecessor key is in profile for
  an Ed25519-only deployment. A deployment that must exclude ML-DSA-keyed
  lineages narrows the revision axis instead — ML-DSA key material is legal
  from `protocol_revision` 3, so `revisions: {1, 2}` excludes it structurally.

  Out-of-profile artifacts fail closed before any cryptographic work, on
  every substrate alike: `:algorithm_outside_profile` or
  `:revision_outside_profile`, never a signature verdict. A malformed
  profile fails closed with `:invalid_profile` before verification begins,
  exactly as a malformed limits value fails with `:invalid_limits`.
  """

  alias CharterAgreementProtocol.{Algorithm, Error}

  @enforce_keys [:algorithms, :revisions]
  defstruct [:algorithms, :revisions]

  @type revision_range :: {pos_integer(), pos_integer()}
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
  Build a caller-supplied profile, rejecting unknown names and out-of-range
  revision bounds.

  Options: `:algorithms` (a non-empty duplicate-free list of registry `alg`
  names; omitted means all) and `:revisions` (`{min, max}` inside the
  accepted set with `min <= max`; omitted means the full accepted range).
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options \\ []) do
    if valid_options?(options) do
      full = full()

      algorithms =
        case Keyword.fetch(options, :algorithms) do
          {:ok, names} -> names
          :error -> full.algorithms
        end

      revisions =
        case Keyword.fetch(options, :revisions) do
          {:ok, bounds} -> bounds
          :error -> full.revisions
        end

      {:ok, %__MODULE__{algorithms: algorithms, revisions: revisions}}
    else
      {:error, Error.new(:invalid_profile, ["profile"])}
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

  defp valid_revisions_option?(bounds), do: valid_range?(bounds, Algorithm.accepted_protocol_revisions())
end
