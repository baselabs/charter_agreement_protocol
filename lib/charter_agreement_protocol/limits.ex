defmodule CharterAgreementProtocol.Limits do
  @moduledoc """
  CAP never authorizes.

  Caller-supplied ceilings for bounded protocol decoding.

  Callers may narrow the defaults or widen them only as far as the compiled
  maximums. The values are pure data: no environment or application config is
  consulted.
  """

  alias CharterAgreementProtocol.Error

  @fields [
    :max_bytes,
    :max_depth,
    :max_object_members,
    :max_array_items,
    :max_string_bytes,
    :max_artifact_set_items
  ]

  @defaults [
    max_bytes: 1_048_576,
    max_depth: 64,
    max_object_members: 1_024,
    max_array_items: 4_096,
    max_string_bytes: 65_536,
    max_artifact_set_items: 1_024
  ]

  @maximums %{
    max_bytes: 16_777_216,
    max_depth: 128,
    max_object_members: 65_536,
    max_array_items: 65_536,
    max_string_bytes: 1_048_576,
    max_artifact_set_items: 4_096
  }

  @enforce_keys @fields
  defstruct @defaults

  @type t :: %__MODULE__{
          max_bytes: non_neg_integer(),
          max_depth: non_neg_integer(),
          max_object_members: non_neg_integer(),
          max_array_items: non_neg_integer(),
          max_string_bytes: non_neg_integer(),
          max_artifact_set_items: non_neg_integer()
        }

  @doc "The closed limit-field set."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc "The default bounded-decoding limits."
  @spec default() :: t()
  def default, do: struct!(__MODULE__, @defaults)

  @doc "The greatest caller-selectable value for each limit."
  @spec maximums() :: t()
  def maximums, do: struct!(__MODULE__, @maximums)

  @doc "Build caller-supplied limits, rejecting unknown or out-of-range values."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options \\ []) do
    if valid_options?(options) do
      {:ok, struct!(__MODULE__, Map.merge(Map.new(@defaults), Map.new(options)))}
    else
      invalid()
    end
  end

  @doc "Whether a limits struct is complete and within the compiled maximums."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = limits) do
    Enum.all?(@fields, fn field ->
      value = Map.fetch!(limits, field)
      is_integer(value) and value >= 0 and value <= Map.fetch!(@maximums, field)
    end)
  end

  def valid?(_limits), do: false

  defp valid_options?(options) when is_list(options) do
    if Keyword.keyword?(options) do
      keys = Keyword.keys(options)

      keys == Enum.uniq(keys) and Enum.all?(keys, &(&1 in @fields)) and
        Enum.all?(options, fn {field, value} ->
          is_integer(value) and value >= 0 and value <= Map.fetch!(@maximums, field)
        end)
    else
      false
    end
  end

  defp valid_options?(_options), do: false

  defp invalid, do: {:error, Error.new(:invalid_limits, ["limits"])}
end
