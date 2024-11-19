defmodule ColouredFlow.Notation.ValTest do
  use ExUnit.Case, async: true

  import ColouredFlow.Notation.Val

  alias ColouredFlow.Definition.Constant

  describe "val/1" do
    test "works" do
      assert %Constant{name: :name, colour_set: :string, value: "Alice"} ===
               val(name :: string() = "Alice")

      assert val(name :: string = "Alice") === val(name() :: string() = "Alice")

      assert_raise RuntimeError, ~r/Invalid name for the constant/, fn ->
        Code.eval_quoted(
          quote do
            val Name :: string() = "Alice"
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid name for the constant: `name\(t\)`/, fn ->
        Code.eval_quoted(
          quote do
            val name(t) :: string() = "Alice"
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid colour_set for the constant/, fn ->
        Code.eval_quoted(
          quote do
            val name :: {binary(), binary()} = {"Alice", "Bob"}
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid colour_set for the constant: `string\(t\)`/, fn ->
        Code.eval_quoted(
          quote do
            val name :: string(t) = "Alice"
          end
        )
      end

      assert_raise RuntimeError, ~r/Invalid Constant declaration/, fn ->
        Code.eval_quoted(
          quote do
            val name :: string()
          end
        )
      end
    end
  end
end
