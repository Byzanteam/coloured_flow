defmodule ColouredFlow.DSL.FunctionTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.Procedure

  describe "function/2 single-line form" do
    test "declares a procedure with single-line body" do
      defmodule SingleLineFun do
        use ColouredFlow.DSL

        name("SingleLineFun")

        colset int() :: integer()
        colset bool() :: boolean()

        function(is_even(x) :: bool(), do: Integer.mod(x, 2) === 0)

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :t do
          input(:input, bind({1, x}))
          output(:output, {1, x})
        end
      end

      cpnet = SingleLineFun.cpnet()

      assert [%Procedure{name: :is_even} = procedure] = cpnet.functions
      # `:bool` is a user-defined colour set wrapping `:boolean`. The Builder
      # resolves the procedure result to the underlying primitive descr.
      assert procedure.result == {:boolean, []}
    end
  end

  describe "function/2 multi-line form" do
    test "declares a procedure with do block" do
      defmodule MultiLineFun do
        use ColouredFlow.DSL

        name("MultiLineFun")

        colset int() :: integer()

        function double(x) :: int() do
          x * 2
        end

        var x :: int()

        place(:input, :int)
        place(:output, :int)

        transition :t do
          input(:input, bind({1, x}))
          output(:output, {1, x})
        end
      end

      cpnet = MultiLineFun.cpnet()

      assert [%Procedure{name: :double} = procedure] = cpnet.functions
      # `:int` is a user-defined colour set wrapping `:integer`. The Builder
      # resolves the procedure result to the underlying primitive descr.
      assert procedure.result == {:integer, []}
    end
  end

  describe "result-type resolution" do
    test "resolves nested compound colour sets recursively" do
      defmodule NestedTupleFun do
        use ColouredFlow.DSL

        name("NestedTupleFun")

        colset int() :: integer()
        colset bool() :: boolean()
        colset my_pair() :: {int(), bool()}

        function pack(x, b) :: my_pair() do
          {x, b}
        end

        var x :: int()
        var b :: bool()

        place(:input, :int)
        place(:output, :int)

        transition :t do
          input(:input, bind({1, x}))
          output(:output, {1, x})
        end
      end

      cpnet = NestedTupleFun.cpnet()

      assert [%Procedure{name: :pack} = procedure] = cpnet.functions
      assert procedure.result == {:tuple, [{:integer, []}, {:boolean, []}]}
    end
  end

  describe "function/2 validation" do
    test "rejects unused declared args at compile time" do
      assert_raise CompileError, ~r/not referenced/i, fn ->
        defmodule UnusedArg do
          use ColouredFlow.DSL

          name("UnusedArg")

          colset int() :: integer()

          function constant_one(x) :: int() do
            1
          end

          var x :: int()

          place(:input, :int)
          place(:output, :int)

          transition :t do
            input(:input, bind({1, x}))
            output(:output, {1, x})
          end
        end
      end
    end
  end
end
