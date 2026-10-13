defmodule CharterAgreementProtocol.Limits do
  @moduledoc """
  Size bounds for decoding and verification. CAP never authorizes; limits
  only bound how much input it will read.

  Every artifact decode and verify call in `CharterAgreementProtocol` takes
  a `Limits` value. Lower-level helpers such as
  `CharterAgreementProtocol.Canonicalization.verify/1` do not. Input bytes
  and the artifact-set bounds are checked before parsing; nesting depth,
  member and item counts and string sizes are checked while the JSON is
  parsed. The exact bound is accepted: one more fails with the value-free
  `:limit_exceeded` error. Limits are plain data. CAP reads no
  environment or application config for them.

  Start from `default/0`. Use `new/1` to tighten a field, or to raise it as
  far as `maximums/0` allows.

  ## Fields

  | Field | Bounds | Default | Greatest |
  |---|---|---:|---:|
  | `max_bytes` | bytes in one input (a revision, or one compact JWS) | 1,048,576 | 16,777,216 |
  | `max_depth` | JSON nesting depth | 64 | 128 |
  | `max_object_members` | members in one JSON object | 1,024 | 65,536 |
  | `max_array_items` | items in one JSON array | 4,096 | 65,536 |
  | `max_string_bytes` | UTF-8 bytes in one string or member name, after unescaping | 65,536 | 1,048,576 |
  | `max_artifact_set_items` | artifacts in each list passed to a set-level call | 1,024 | 4,096 |
  | `max_artifact_set_bytes` | total artifact bytes in one `verify_chain` call | 67,108,864 | 1,073,741,824 |

  `max_artifact_set_items` applies to each list given to
  `CharterAgreementProtocol.verify_chain/5` and to the list given to
  `CharterAgreementProtocol.verify_descriptor_chain/2`.
  `max_artifact_set_bytes` applies to `verify_chain/5`, including the one
  `CharterAgreementProtocol.verify_receipt/3` runs on chain facts. Both
  checks run before any decoding or signature work.

  ## Examples

      iex> {:ok, limits} = CharterAgreementProtocol.Limits.new(max_depth: 16)
      iex> limits.max_depth
      16
      iex> CharterAgreementProtocol.Limits.new(max_depth: 129)
      {:error, %CharterAgreementProtocol.Error{code: :invalid_limits, subject: ["limits"], detail: nil}}
      iex> CharterAgreementProtocol.Limits.new(max_widgets: 1)
      {:error, %CharterAgreementProtocol.Error{code: :invalid_limits, subject: ["limits"], detail: nil}}
  """

  alias CharterAgreementProtocol.Error

  @fields [
    :max_bytes,
    :max_depth,
    :max_object_members,
    :max_array_items,
    :max_string_bytes,
    :max_artifact_set_items,
    :max_artifact_set_bytes
  ]

  @defaults [
    max_bytes: 1_048_576,
    max_depth: 64,
    max_object_members: 1_024,
    max_array_items: 4_096,
    max_string_bytes: 65_536,
    max_artifact_set_items: 1_024,
    max_artifact_set_bytes: 67_108_864
  ]

  @maximums %{
    max_bytes: 16_777_216,
    max_depth: 128,
    max_object_members: 65_536,
    max_array_items: 65_536,
    max_string_bytes: 1_048_576,
    max_artifact_set_items: 4_096,
    max_artifact_set_bytes: 1_073_741_824
  }

  @enforce_keys @fields
  defstruct @defaults

  @typedoc "One complete set of limits. See the module doc for each field."
  @type t :: %__MODULE__{
          max_bytes: non_neg_integer(),
          max_depth: non_neg_integer(),
          max_object_members: non_neg_integer(),
          max_array_items: non_neg_integer(),
          max_string_bytes: non_neg_integer(),
          max_artifact_set_items: non_neg_integer(),
          max_artifact_set_bytes: non_neg_integer()
        }

  @doc "The field names a `Limits` value has, in order."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc "The default limits. See the module doc for each value."
  @spec default() :: t()
  def default, do: struct!(__MODULE__, @defaults)

  @doc "The greatest value `new/1` accepts for each field."
  @spec maximums() :: t()
  def maximums, do: struct!(__MODULE__, @maximums)

  @doc """
  Build limits from the defaults plus the fields you give.

  Each value must be a non-negative integer no greater than its maximum.
  Unknown fields, repeated fields and out-of-range values return
  `:invalid_limits`.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options \\ []) do
    if valid_options?(options) do
      {:ok, struct!(__MODULE__, Map.merge(Map.new(@defaults), Map.new(options)))}
    else
      invalid()
    end
  end

  @doc "Whether a value is a complete `Limits` struct within the maximums."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = limits) do
    Enum.all?(@fields, fn field ->
      value = Map.get(limits, field)
      is_integer(value) and value >= 0 and value <= Map.fetch!(@maximums, field)
    end)
  end

  def valid?(_limits), do: false

  @doc false
  @spec check(term()) :: :ok | {:error, Error.t()}
  def check(value), do: if(valid?(value), do: :ok, else: invalid())

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
