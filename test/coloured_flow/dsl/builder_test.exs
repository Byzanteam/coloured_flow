defmodule ColouredFlow.DSL.BuilderTest do
  use ExUnit.Case, async: true

  describe "validator-driven errors point to the offending declaration" do
    test "place referencing an unknown colour set points at the place call site" do
      source = """
      defmodule ColouredFlow.DSL.BuilderTest.PlaceUnknownColset do
        use ColouredFlow.DSL

        name "PlaceUnknownColset"

        colset int() :: integer()

        var x :: int()

        place :input, :int
        place :output, :ghost

        transition :t do
          input :input, bind({1, x})
          output :output, {1, x}
        end
      end
      """

      error =
        assert_raise CompileError, ~r/colour set|undefined|unknown/i, fn ->
          Code.compile_string(source, "place_unknown_colset.exs")
        end

      assert error.file == "place_unknown_colset.exs"
      # Points at `place :output, :ghost` (line 11, 1-indexed).
      assert error.line == 11
    end

    test "duplicate function name points at the second declaration" do
      source = """
      defmodule ColouredFlow.DSL.BuilderTest.DuplicateFunction do
        use ColouredFlow.DSL

        name "DuplicateFunction"

        colset int() :: integer()

        function double(x) :: int() do
          x * 2
        end

        function double(x) :: int() do
          x * 3
        end

        var x :: int()

        place :input, :int
        place :output, :int

        transition :t do
          input :input, bind({1, x})
          output :output, {1, x}
        end
      end
      """

      error =
        assert_raise CompileError, ~r/unique|duplicate|already/i, fn ->
          Code.compile_string(source, "duplicate_function.exs")
        end

      assert error.file == "duplicate_function.exs"
      # Points at the second `function double(x)` (line 12, 1-indexed).
      assert error.line == 12
    end

    test "duplicate colset name points at the second declaration" do
      source = """
      defmodule ColouredFlow.DSL.BuilderTest.DuplicateColset do
        use ColouredFlow.DSL

        name "DuplicateColset"

        colset int() :: integer()
        colset int() :: integer()

        var x :: int()

        place :input, :int
        place :output, :int

        transition :t do
          input :input, bind({1, x})
          output :output, {1, x}
        end
      end
      """

      error =
        assert_raise CompileError, ~r/unique|duplicate|already/i, fn ->
          Code.compile_string(source, "duplicate_colset.exs")
        end

      assert error.file == "duplicate_colset.exs"
      # Points at the second `colset int()` (line 7, 1-indexed).
      assert error.line == 7
    end
  end
end
