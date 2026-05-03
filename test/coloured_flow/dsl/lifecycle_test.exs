defmodule ColouredFlow.DSL.LifecycleTest do
  use ExUnit.Case, async: true

  describe "uniqueness" do
    test "duplicate on_enactment_start raises CompileError" do
      assert_raise CompileError, ~r/on_enactment_start already declared/, fn ->
        Code.eval_string("""
        defmodule ColouredFlow.DSL.LifecycleTest.DuplicateStart do
          use ColouredFlow.DSL

          name "dup"

          colset int() :: integer()
          var x :: int()

          place :p, :int

          transition :t do
            input :p, bind({1, x})
            output :p, {1, x}
          end

          on_enactment_start do
            :ok
          end

          on_enactment_start do
            :other
          end
        end
        """)
      end
    end

    test "duplicate on_enactment_terminate raises CompileError" do
      assert_raise CompileError, ~r/on_enactment_terminate already declared/, fn ->
        Code.eval_string("""
        defmodule ColouredFlow.DSL.LifecycleTest.DuplicateTerminate do
          use ColouredFlow.DSL

          name "dup_term"

          colset int() :: integer()
          var x :: int()

          place :p, :int

          transition :t do
            input :p, bind({1, x})
            output :p, {1, x}
          end

          on_enactment_terminate do
            :ok
          end

          on_enactment_terminate reason do
            send(self(), {:terminated, reason})
          end
        end
        """)
      end
    end
  end

  describe "compiles when each hook appears at most once" do
    test "single on_enactment_start succeeds" do
      defmodule SingleStart do
        use ColouredFlow.DSL

        name "single_start"

        colset int() :: integer()
        var x :: int()

        place :p, :int

        transition :t do
          input :p, bind({1, x})
          output :p, {1, x}
        end

        on_enactment_start do
          :ok
        end
      end

      assert function_exported?(SingleStart, :on_enactment_start, 1)
    end
  end
end
