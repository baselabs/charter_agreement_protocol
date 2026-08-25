defmodule CharterAgreementProtocol.Architecture.ConstantTimeCompareShapeTest do
  use ExUnit.Case, async: true

  @source Path.expand("../../lib/charter_agreement_protocol/digest.ex", __DIR__)

  test "digest equality consumes every byte pair before one final accumulator test" do
    assert [recursive, base] = function_bodies(ast(), :xor_zero?)

    assert {:xor_zero?, _,
            [
              _,
              _,
              {{:., _, [{:__aliases__, _, [:Bitwise]}, :bor]}, _,
               [
                 {{:., _, [{:__aliases__, _, [:Bitwise]}, :bxor]}, _, [_, _]},
                 _
               ]}
            ]} = recursive

    assert {:==, _, [_, 0]} = base
  end

  test "public digest equality reaches bytes only through the accumulating loop" do
    assert [body, false] = function_bodies(ast(), :equal?)

    {_body, calls} =
      Macro.prewalk(body, [], fn
        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    assert :xor_zero? in calls
  end

  defp ast do
    @source |> File.read!() |> Code.string_to_quoted!()
  end

  defp function_bodies(ast, name) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {kind, _, [{^name, _, _}, [do: body]]} = node, acc when kind in [:def, :defp] ->
          {node, [body | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(bodies)
  end
end
