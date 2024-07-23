defmodule ColouredFlow.Notation.VarTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Notation.Var

  alias ColouredFlow.Definition.Variable

  describe "var/1" do
    test "works" do
      assert %Variable{name: :name, colour_set: :string} === var(name :: string())
      assert var(name :: string) === var(name() :: string())

      assert_raise RuntimeError, ~r/Invalid name for the variable/, fn ->
        Code.eval_quoted(
          quote do
            var Name :: string
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid colour_set for the variable/, fn ->
        Code.eval_quoted(
          quote do
            var name :: {binary(), binary()}
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid variable declaration/, fn ->
        Code.eval_quoted(
          quote do
            var name
          end
        )
      end
    end
  end
end
