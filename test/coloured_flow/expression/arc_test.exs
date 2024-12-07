defmodule ColouredFlow.Expression.ArcTest do
  use ExUnit.Case, async: true

  doctest ColouredFlow.Expression.Arc, import: true

  import ColouredFlow.Expression.Arc, only: [bind: 1]

  describe "bind evaluation" do
    test "works" do
      quoted = quote(do: bind({1, 2}))
      assert {{:ok, {1, 2}}, _binding} = Code.eval_quoted(quoted)

      quoted = quote(do: bind({x, y}))
      assert {{:ok, {1, 2}}, _binding} = Code.eval_quoted(quoted, make_binding(x: 1, y: 2))

      quoted = quote(do: bind({x, {1, 2}}))
      assert {{:ok, {1, {1, 2}}}, _binding} = Code.eval_quoted(quoted, make_binding(x: 1))

      quoted = quote(do: bind({x, {1, y}}))
      assert {{:ok, {1, {1, 2}}}, _binding} = Code.eval_quoted(quoted, make_binding(x: 1, y: 2))

      quoted = quote(do: bind({x, y, z}))

      assert_raise ArgumentError, ~r/Invalid bind expression/, fn ->
        Code.eval_quoted(quoted, make_binding(x: 1, y: 2, z: 3))
      end
    end

    test "support guards" do
      quoted = quote do: bind({x, y} when x > y)
      assert {{:ok, {2, 1}}, _binding} = Code.eval_quoted(quoted, make_binding(x: 2, y: 1))
      assert {:error, _binding} = Code.eval_quoted(quoted, make_binding(x: 2, y: 2))

      quoted = quote do: bind({x, y} when x > 5 when x < 5 and x > y)
      assert {{:ok, {6, 7}}, _binding} = Code.eval_quoted(quoted, make_binding(x: 6, y: 7))
      assert {{:ok, {2, 1}}, _binding} = Code.eval_quoted(quoted, make_binding(x: 2, y: 1))

      quoted = quote do: bind({x, [1 | y]})
      assert {{:ok, {2, [1, 2]}}, _binding} = Code.eval_quoted(quoted, make_binding(x: 2, y: [2]))

      quoted = quote do: bind({x, [1 | y]} when length(y) > 1)
      assert {:error, _binding} = Code.eval_quoted(quoted, make_binding(x: 2, y: [2]))

      assert {{:ok, {2, [1, 2, 3]}}, _binding} =
               Code.eval_quoted(quoted, make_binding(x: 2, y: [2, 3]))
    end
  end

  defp make_binding(binding) do
    Enum.map(binding, fn {name, value} -> {{name, __MODULE__}, value} end)
  end
end
