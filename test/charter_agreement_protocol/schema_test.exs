defmodule CharterAgreementProtocol.SchemaTest do
  use ExUnit.Case, async: true

  alias CharterAgreementProtocol.{Error, Schema}

  test "a table-valid closed object is returned unchanged" do
    value = valid_value()
    assert Schema.validate(definition(), value) == {:ok, value}
  end

  test "a non-object reaches the type stage" do
    assert_error(Schema.validate(definition(), {:array, []}), :invalid_type, ["sample"])
  end

  test "unknown member outranks missing required regardless of input order" do
    members = [{"rogue", {:integer, 1}} | valid_members() |> delete("required") |> Enum.reverse()]
    assert_error(Schema.validate(definition(), {:object, members}), :unknown_member, ["sample"])
  end

  test "missing required outranks a present type defect" do
    members = valid_members() |> delete("required") |> put("typed", {:string, "wrong"})

    assert_error(Schema.validate(definition(), {:object, members}), :missing_required, [
      "sample",
      "required"
    ])
  end

  test "type outranks constraint" do
    members =
      valid_members() |> put("typed", {:string, "wrong"}) |> put("bounded", {:string, "!"})

    assert_error(Schema.validate(definition(), {:object, members}), :invalid_type, [
      "sample",
      "typed"
    ])
  end

  test "constraint outranks cardinality" do
    members = put(valid_members(), "bounded", {:string, "!"})

    assert_error(Schema.validate(definition(), {:object, members}), :constraint_violation, [
      "sample",
      "bounded"
    ])
  end

  test "cardinality outranks nested validation" do
    members =
      valid_members()
      |> put("bounded", {:string, "a"})
      |> put("nested", {:object, []})

    assert_error(Schema.validate(definition(), {:object, members}), :cardinality_violation, [
      "sample",
      "bounded"
    ])
  end

  test "nested validation outranks cross-field validation" do
    members =
      valid_members()
      |> put("required", {:string, "wrong"})
      |> put("nested", {:object, []})

    assert_error(Schema.validate(definition(), {:object, members}), :nested_invalid, [
      "sample",
      "nested"
    ])
  end

  test "cross-field validation is the final stage" do
    members = put(valid_members(), "required", {:string, "wrong"})

    assert_error(Schema.validate(definition(), {:object, members}), :cross_field_invalid, [
      "sample"
    ])
  end

  test "field declaration order, not document order, chooses same-stage subjects" do
    members =
      valid_members()
      |> put("typed", {:string, "wrong"})
      |> put("bounded", {:integer, 1})
      |> Enum.reverse()

    assert_error(Schema.validate(definition(), {:object, members}), :invalid_type, [
      "sample",
      "typed"
    ])
  end

  test "nested arrays validate each item and retain the outer schema subject" do
    definition =
      Schema.definition("array_sample", [
        Schema.field("items", types: [:array], nested: {:array, child_definition()})
      ])

    good = {:object, [{"items", {:array, [{:object, [{"child", {:string, "ok"}}]}]}}]}
    bad = {:object, [{"items", {:array, [{:object, []}]}}]}

    assert Schema.validate(definition, good) == {:ok, good}
    assert_error(Schema.validate(definition, bad), :nested_invalid, ["array_sample", "items"])
  end

  test "malformed constructed objects and non-definitions fail as typed errors" do
    assert_error(Schema.validate(definition(), {:object, [{"bad"}]}), :invalid_type, ["sample"])

    assert_error(
      Schema.validate(
        definition(),
        {:object, [{"required", {:string, "ok"}}, {"required", :null}]}
      ),
      :invalid_type,
      ["sample"]
    )

    assert_error(Schema.validate(:not_a_definition, valid_value()), :invalid_type, ["schema"])
  end

  test "invalid protocol-owned definitions fail loudly at construction" do
    field = Schema.field("name", types: [:string])

    assert_raise ArgumentError, fn -> Schema.definition("bad", [field, field]) end
    assert_raise ArgumentError, fn -> Schema.field("bad", types: [:string], cardinality: :bad) end

    assert_raise ArgumentError, fn ->
      Schema.field("bad", types: [:integer], cardinality: {0, 1})
    end

    assert_raise ArgumentError, fn -> Schema.field("bad", types: [:string], nested: :bad) end

    assert_raise ArgumentError, fn ->
      Schema.field("bad", types: [:string], constraint: {:one_of, []})
    end

    assert_raise ArgumentError, fn ->
      Schema.field("bad", types: [:string], constraint: {:all, []})
    end

    assert_raise ArgumentError, fn -> Schema.field("bad", types: [:string], constraint: :bad) end

    assert_raise ArgumentError, fn ->
      Schema.field("bad", types: [:string], nested: {:scalar, child_definition()})
    end

    assert_raise ArgumentError, fn ->
      Schema.field("bad", types: [:array, :null], nested: {:array, child_definition()})
    end

    assert_raise ArgumentError, fn ->
      Schema.definition("bad", [field], cross_field: [{:ordered, "a", :bad, "b"}])
    end

    assert_raise ArgumentError, fn ->
      Schema.definition("bad", [field], cross_field: [:bad])
    end
  end

  test "forged inconsistent definitions return typed errors instead of executing" do
    child = child_definition()
    array = Schema.field("items", types: [:array], nested: {:array, child})
    number = Schema.field("number", types: [:integer])

    nested_forgery =
      %{
        Schema.definition("nested_forgery", [array])
        | fields: [%{array | types: [:array, :null]}]
      }

    cardinality_forgery =
      %{
        Schema.definition("cardinality_forgery", [number])
        | fields: [%{number | cardinality: {0, 1}}]
      }

    assert_error(
      Schema.validate(nested_forgery, {:object, [{"items", :null}]}),
      :invalid_type,
      ["schema"]
    )

    assert_error(
      Schema.validate(cardinality_forgery, {:object, [{"number", {:integer, 1}}]}),
      :invalid_type,
      ["schema"]
    )
  end

  test "optional absence and every tagged scalar type validate" do
    scalar_definition =
      Schema.definition("scalars", [
        Schema.field("null", types: [:null]),
        Schema.field("boolean", types: [:boolean]),
        Schema.field("integer", types: [:integer]),
        Schema.field("float", types: [:float]),
        Schema.field("number_integer", types: [:number]),
        Schema.field("number_float", types: [:number]),
        Schema.field("optional", types: [:string])
      ])

    value =
      {:object,
       [
         {"null", :null},
         {"boolean", {:boolean, true}},
         {"integer", {:integer, 1}},
         {"float", {:float, 1.5}},
         {"number_integer", {:integer, 2}},
         {"number_float", {:float, 2.5}}
       ]}

    assert Schema.validate(scalar_definition, value) == {:ok, value}
  end

  test "array and object cardinalities are measured independently" do
    definition =
      Schema.definition("collections", [
        Schema.field("array", types: [:array], cardinality: {1, 1}),
        Schema.field("object", types: [:object], cardinality: {1, 1})
      ])

    value = {:object, [{"array", {:array, [:null]}}, {"object", {:object, [{"a", :null}]}}]}
    assert Schema.validate(definition, value) == {:ok, value}
  end

  test "the constraint algebra is closed data and composes without callbacks" do
    definition =
      Schema.definition("constraints", [
        Schema.field("integer", types: [:integer], constraint: {:integer_range, 1, 2}),
        Schema.field("bytes", types: [:string], constraint: {:string_bytes, 2, 4}),
        Schema.field("choice", types: [:string], constraint: {:one_of, [{:string, "yes"}]}),
        Schema.field("match", types: [:string], constraint: {:matches, ~r/\Aok\z/}),
        Schema.field("all",
          types: [:string],
          constraint: {:all, [{:string_bytes, 2, 2}, {:matches, ~r/\Aok\z/}]}
        )
      ])

    value =
      {:object,
       [
         {"integer", {:integer, 1}},
         {"bytes", {:string, "ok"}},
         {"choice", {:string, "yes"}},
         {"match", {:string, "ok"}},
         {"all", {:string, "ok"}}
       ]}

    assert Schema.validate(definition, value) == {:ok, value}
    refute contains_function?(definition)

    mismatched =
      Schema.definition("mismatched", [
        Schema.field("field", types: [:integer], constraint: {:matches, ~r/.*/})
      ])

    assert_error(
      Schema.validate(mismatched, {:object, [{"field", {:integer, 1}}]}),
      :constraint_violation,
      ["mismatched", "field"]
    )
  end

  test "the cross-field algebra covers equality, order, allowed tuples, and requirements" do
    fields = [
      Schema.field("a", types: [:integer]),
      Schema.field("a_copy", types: [:integer]),
      Schema.field("b", types: [:integer]),
      Schema.field("left_text", types: [:string]),
      Schema.field("right_text", types: [:string]),
      Schema.field("mode", types: [:string]),
      Schema.field("detail", types: [:string])
    ]

    rules = [
      {:field_equals, "a", {:integer, 1}},
      {:fields_equal, "a", "a_copy"},
      {:ordered, "a", :lt, "b"},
      {:ordered, "a", :lte, "b"},
      {:ordered, "b", :gt, "a"},
      {:ordered, "b", :gte, "a"},
      {:ordered, "left_text", :lte, "right_text"},
      {:allowed, ["mode"], [[{:string, "ok"}], [{:string, "error"}]]},
      {:requires, "mode", {:string, "error"}, "detail"}
    ]

    definition = Schema.definition("cross", fields, cross_field: rules)

    members = [
      {"a", {:integer, 1}},
      {"a_copy", {:integer, 1}},
      {"b", {:integer, 2}},
      {"left_text", {:string, "a"}},
      {"right_text", {:string, "b"}},
      {"mode", {:string, "error"}},
      {"detail", {:string, "present"}}
    ]

    assert Schema.validate(definition, {:object, members}) == {:ok, {:object, members}}

    missing_detail = delete(members, "detail")

    assert_error(
      Schema.validate(definition, {:object, missing_detail}),
      :cross_field_invalid,
      ["cross"]
    )

    missing_ordered =
      Schema.definition("missing_ordered", fields, cross_field: [{:ordered, "a", :lt, "detail"}])

    assert_error(
      Schema.validate(missing_ordered, {:object, missing_detail}),
      :cross_field_invalid,
      ["missing_ordered"]
    )

    wrong_ordered =
      Schema.definition(
        "wrong_ordered",
        [Schema.field("a", types: [:boolean]), Schema.field("b", types: [:boolean])],
        cross_field: [{:ordered, "a", :lt, "b"}]
      )

    assert_error(
      Schema.validate(
        wrong_ordered,
        {:object, [{"a", {:boolean, false}}, {"b", {:boolean, true}}]}
      ),
      :cross_field_invalid,
      ["wrong_ordered"]
    )
  end

  defp definition do
    Schema.definition(
      "sample",
      [
        Schema.field("required", required?: true, types: [:string]),
        Schema.field("typed", types: [:integer], constraint: {:integer_range, 1, 10}),
        Schema.field("bounded",
          types: [:string],
          constraint: {:matches, ~r/\A[^!]*\z/u},
          cardinality: {2, 4}
        ),
        Schema.field("nested", types: [:object], nested: {:object, child_definition()})
      ],
      cross_field: [{:field_equals, "required", {:string, "ok"}}]
    )
  end

  defp child_definition do
    Schema.definition("child", [Schema.field("child", required?: true, types: [:string])])
  end

  defp valid_value, do: {:object, valid_members()}

  defp valid_members do
    [
      {"required", {:string, "ok"}},
      {"typed", {:integer, 1}},
      {"bounded", {:string, "abcd"}},
      {"nested", {:object, [{"child", {:string, "ok"}}]}}
    ]
  end

  defp delete(members, name), do: Enum.reject(members, &(elem(&1, 0) == name))
  defp put(members, name, value), do: List.keystore(members, name, 0, {name, value})

  defp contains_function?(term) when is_function(term), do: true

  defp contains_function?(term) when is_map(term),
    do: term |> Map.from_struct() |> Map.values() |> Enum.any?(&contains_function?/1)

  defp contains_function?(term) when is_list(term), do: Enum.any?(term, &contains_function?/1)

  defp contains_function?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&contains_function?/1)

  defp contains_function?(_term), do: false

  defp assert_error(result, code, subject) do
    assert {:error, %Error{code: ^code, subject: ^subject, detail: nil}} = result
  end
end
