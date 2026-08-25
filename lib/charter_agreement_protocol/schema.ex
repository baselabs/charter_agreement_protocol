defmodule CharterAgreementProtocol.Schema do
  @moduledoc """
  Closed, table-driven validation for protocol-owned artifact definitions.

  Validation always completes one whole stage before entering the next:
  unknown member, missing required, type, constraint, cardinality, nested, and
  cross-field. Field declaration order chooses same-stage subjects; document
  member order never chooses a verdict.
  """

  alias CharterAgreementProtocol.Error

  defmodule Field do
    @moduledoc "A protocol-owned field declaration consumed by `Schema.validate/2`."
    @enforce_keys [:name, :types]
    defstruct [:name, :types, required?: false, constraint: nil, cardinality: nil, nested: nil]

    @type value_type ::
            :null | :boolean | :integer | :float | :number | :string | :array | :object

    @type constraint ::
            {:integer_range, integer(), integer()}
            | {:string_bytes, non_neg_integer(), non_neg_integer()}
            | {:one_of, [CharterAgreementProtocol.Json.value()]}
            | {:matches, Regex.t()}
            | {:all, [constraint()]}

    @type t :: %__MODULE__{
            name: binary(),
            types: [value_type()],
            required?: boolean(),
            constraint: nil | constraint(),
            cardinality: nil | {non_neg_integer(), non_neg_integer()},
            nested: nil | {:object | :array, CharterAgreementProtocol.Schema.Definition.t()}
          }
  end

  defmodule Definition do
    @moduledoc "A closed object definition and its final declarative cross-field rules."
    @enforce_keys [:name, :fields]
    defstruct [:name, :fields, cross_field: []]

    @type cross_rule ::
            {:field_equals, binary(), CharterAgreementProtocol.Json.value()}
            | {:fields_equal, binary(), binary()}
            | {:ordered, binary(), :lt | :lte | :gt | :gte, binary()}
            | {:allowed, [binary()], [[CharterAgreementProtocol.Json.value()]]}
            | {:requires, binary(), CharterAgreementProtocol.Json.value(), binary()}

    @type t :: %__MODULE__{
            name: binary(),
            fields: [CharterAgreementProtocol.Schema.Field.t()],
            cross_field: [cross_rule()]
          }
  end

  alias __MODULE__.{Definition, Field}

  @types [:null, :boolean, :integer, :float, :number, :string, :array, :object]

  @doc "Build one protocol-owned field declaration. Invalid declarations fail loudly."
  @spec field(binary(), keyword()) :: Field.t()
  def field(name, options) when is_binary(name) and is_list(options) do
    options =
      Keyword.validate!(options,
        required?: false,
        types: nil,
        constraint: nil,
        cardinality: nil,
        nested: nil
      )

    field = struct!(Field, Keyword.put(options, :name, name))
    if valid_field?(field), do: field, else: raise(ArgumentError, "invalid schema field")
  end

  @doc "Build a protocol-owned closed-object definition. Invalid definitions fail loudly."
  @spec definition(binary(), [Field.t()], keyword()) :: Definition.t()
  def definition(name, fields, options \\ [])
      when is_binary(name) and is_list(fields) and is_list(options) do
    options = Keyword.validate!(options, cross_field: [])
    definition = struct!(Definition, Keyword.merge(options, name: name, fields: fields))

    if valid_definition?(definition),
      do: definition,
      else: raise(ArgumentError, "invalid schema definition")
  end

  @doc "Validate one tagged object against a protocol-owned definition."
  @spec validate(Definition.t(), CharterAgreementProtocol.Json.value()) ::
          {:ok, CharterAgreementProtocol.Json.value()} | {:error, Error.t()}
  def validate(%Definition{} = definition, {:object, members} = value) when is_list(members) do
    if valid_members?(members) do
      member_map = Map.new(members)

      with :ok <- reject_unknown(definition, member_map),
           :ok <- require_members(definition, member_map),
           :ok <- validate_types(definition, member_map),
           :ok <- validate_constraints(definition, member_map),
           :ok <- validate_cardinalities(definition, member_map),
           :ok <- validate_nested(definition, member_map),
           :ok <- validate_cross_field(definition, member_map) do
        {:ok, value}
      end
    else
      error(:invalid_type, [definition.name])
    end
  end

  def validate(%Definition{name: name}, _value), do: error(:invalid_type, [name])
  def validate(_definition, _value), do: error(:invalid_type, ["schema"])

  defp valid_field?(%Field{} = field) do
    field.name != "" and field.types != [] and Enum.all?(field.types, &(&1 in @types)) and
      is_boolean(field.required?) and valid_constraint?(field.constraint) and
      valid_cardinality?(field.cardinality) and valid_nested?(field.nested)
  end

  defp valid_constraint?(nil), do: true

  defp valid_constraint?({:integer_range, minimum, maximum}),
    do: is_integer(minimum) and is_integer(maximum) and minimum <= maximum

  defp valid_constraint?({:string_bytes, minimum, maximum}),
    do: valid_bounds?(minimum, maximum)

  defp valid_constraint?({:one_of, values}), do: is_list(values) and values != []
  defp valid_constraint?({:matches, %Regex{}}), do: true

  defp valid_constraint?({:all, constraints}),
    do:
      is_list(constraints) and constraints != [] and Enum.all?(constraints, &valid_constraint?/1)

  defp valid_constraint?(_constraint), do: false

  defp valid_cardinality?(nil), do: true

  defp valid_cardinality?({minimum, maximum}),
    do: valid_bounds?(minimum, maximum)

  defp valid_cardinality?(_cardinality), do: false

  defp valid_nested?(nil), do: true
  defp valid_nested?({kind, %Definition{}}), do: kind in [:object, :array]
  defp valid_nested?(_nested), do: false

  defp valid_definition?(%Definition{} = definition) do
    names = Enum.map(definition.fields, & &1.name)

    definition.name != "" and Enum.all?(definition.fields, &valid_field?/1) and
      names == Enum.uniq(names) and valid_cross_rules?(definition.cross_field)
  end

  defp valid_members?(members) do
    Enum.all?(members, fn
      {name, _value} when is_binary(name) -> true
      _member -> false
    end) and members |> Enum.map(&elem(&1, 0)) |> then(&(&1 == Enum.uniq(&1)))
  end

  defp reject_unknown(definition, member_map) do
    allowed = MapSet.new(definition.fields, & &1.name)

    if Enum.all?(Map.keys(member_map), &MapSet.member?(allowed, &1)),
      do: :ok,
      else: error(:unknown_member, [definition.name])
  end

  defp require_members(definition, member_map) do
    case Enum.find(definition.fields, &(&1.required? and not Map.has_key?(member_map, &1.name))) do
      nil -> :ok
      field -> error(:missing_required, [definition.name, field.name])
    end
  end

  defp validate_types(definition, member_map) do
    find_field_error(
      definition,
      member_map,
      fn field, value ->
        not Enum.any?(field.types, &type?(&1, value))
      end,
      :invalid_type
    )
  end

  defp validate_constraints(definition, member_map) do
    find_field_error(
      definition,
      member_map,
      fn
        %Field{constraint: nil}, _value -> false
        %Field{constraint: constraint}, value -> not constraint_satisfied?(constraint, value)
      end,
      :constraint_violation
    )
  end

  defp validate_cardinalities(definition, member_map) do
    find_field_error(
      definition,
      member_map,
      fn
        %Field{cardinality: nil}, _value ->
          false

        %Field{cardinality: {minimum, maximum}}, value ->
          cardinality = cardinality(value)
          cardinality < minimum or cardinality > maximum
      end,
      :cardinality_violation
    )
  end

  defp validate_nested(definition, member_map) do
    find_field_error(
      definition,
      member_map,
      fn
        %Field{nested: nil}, _value ->
          false

        %Field{nested: {:object, nested}}, value ->
          not match?({:ok, _}, validate(nested, value))

        %Field{nested: {:array, nested}}, {:array, values} ->
          Enum.any?(values, &(not match?({:ok, _}, validate(nested, &1))))
      end,
      :nested_invalid
    )
  end

  defp validate_cross_field(%Definition{} = definition, member_map) do
    if Enum.all?(definition.cross_field, &cross_rule_satisfied?(&1, member_map)),
      do: :ok,
      else: error(:cross_field_invalid, [definition.name])
  end

  defp find_field_error(definition, member_map, invalid?, code) do
    case Enum.find(definition.fields, &field_invalid?(&1, member_map, invalid?)) do
      nil -> :ok
      field -> error(code, [definition.name, field.name])
    end
  end

  defp field_invalid?(field, member_map, invalid?) do
    case Map.fetch(member_map, field.name) do
      {:ok, value} -> invalid?.(field, value)
      :error -> false
    end
  end

  defp valid_bounds?(minimum, maximum),
    do: is_integer(minimum) and is_integer(maximum) and minimum >= 0 and minimum <= maximum

  defp valid_cross_rules?(rules), do: is_list(rules) and Enum.all?(rules, &valid_cross_rule?/1)

  defp valid_cross_rule?({:field_equals, field, _value}), do: valid_name?(field)

  defp valid_cross_rule?({:fields_equal, left, right}),
    do: valid_name?(left) and valid_name?(right)

  defp valid_cross_rule?({:ordered, left, operator, right}),
    do: valid_name?(left) and operator in [:lt, :lte, :gt, :gte] and valid_name?(right)

  defp valid_cross_rule?({:allowed, fields, tuples}) do
    is_list(fields) and fields != [] and Enum.all?(fields, &valid_name?/1) and is_list(tuples) and
      tuples != [] and Enum.all?(tuples, &(is_list(&1) and length(&1) == length(fields)))
  end

  defp valid_cross_rule?({:requires, field, _value, required_field}),
    do: valid_name?(field) and valid_name?(required_field)

  defp valid_cross_rule?(_rule), do: false

  defp valid_name?(name), do: is_binary(name) and name != ""

  defp constraint_satisfied?({:integer_range, minimum, maximum}, {:integer, value}),
    do: value >= minimum and value <= maximum

  defp constraint_satisfied?({:string_bytes, minimum, maximum}, {:string, value}),
    do: byte_size(value) >= minimum and byte_size(value) <= maximum

  defp constraint_satisfied?({:one_of, values}, value), do: value in values
  defp constraint_satisfied?({:matches, regex}, {:string, value}), do: Regex.match?(regex, value)

  defp constraint_satisfied?({:all, constraints}, value),
    do: Enum.all?(constraints, &constraint_satisfied?(&1, value))

  defp constraint_satisfied?(_constraint, _value), do: false

  defp cross_rule_satisfied?({:field_equals, field, value}, members),
    do: Map.get(members, field) == value

  defp cross_rule_satisfied?({:fields_equal, left, right}, members),
    do: Map.fetch(members, left) == Map.fetch(members, right) and Map.has_key?(members, left)

  defp cross_rule_satisfied?({:ordered, left, operator, right}, members) do
    with {:ok, left_value} <- Map.fetch(members, left),
         {:ok, right_value} <- Map.fetch(members, right) do
      ordered?(left_value, operator, right_value)
    else
      :error -> false
    end
  end

  defp cross_rule_satisfied?({:allowed, fields, tuples}, members),
    do: Enum.map(fields, &Map.get(members, &1)) in tuples

  defp cross_rule_satisfied?({:requires, field, value, required_field}, members) do
    Map.get(members, field) != value or Map.has_key?(members, required_field)
  end

  defp ordered?({:integer, left}, operator, {:integer, right}), do: compare(left, operator, right)
  defp ordered?({:string, left}, operator, {:string, right}), do: compare(left, operator, right)
  defp ordered?(_left, _operator, _right), do: false

  defp compare(left, :lt, right), do: left < right
  defp compare(left, :lte, right), do: left <= right
  defp compare(left, :gt, right), do: left > right
  defp compare(left, :gte, right), do: left >= right

  defp type?(:null, :null), do: true
  defp type?(:boolean, {:boolean, value}), do: is_boolean(value)
  defp type?(:integer, {:integer, value}), do: is_integer(value)
  defp type?(:float, {:float, value}), do: is_float(value)
  defp type?(:number, {:integer, value}), do: is_integer(value)
  defp type?(:number, {:float, value}), do: is_float(value)
  defp type?(:string, {:string, value}), do: is_binary(value)
  defp type?(:array, {:array, value}), do: is_list(value)
  defp type?(:object, {:object, value}), do: is_list(value)
  defp type?(_type, _value), do: false

  defp cardinality({:string, value}), do: byte_size(value)
  defp cardinality({:array, value}), do: length(value)
  defp cardinality({:object, value}), do: length(value)

  defp error(:invalid_type, subject), do: {:error, Error.new(:invalid_type, subject)}
  defp error(:unknown_member, subject), do: {:error, Error.new(:unknown_member, subject)}
  defp error(:missing_required, subject), do: {:error, Error.new(:missing_required, subject)}

  defp error(:constraint_violation, subject),
    do: {:error, Error.new(:constraint_violation, subject)}

  defp error(:cardinality_violation, subject),
    do: {:error, Error.new(:cardinality_violation, subject)}

  defp error(:nested_invalid, subject), do: {:error, Error.new(:nested_invalid, subject)}

  defp error(:cross_field_invalid, subject),
    do: {:error, Error.new(:cross_field_invalid, subject)}
end
