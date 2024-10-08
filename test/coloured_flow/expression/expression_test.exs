defmodule ColouredFlow.ExpressionTest do
  use ExUnit.Case, async: true
  doctest ColouredFlow.Expression, import: true

  alias ColouredFlow.Expression
  alias ColouredFlow.Expression.EvalDiagnostic

  describe "compile/2" do
    test "get free variables" do
      assert MapSet.new([]) === get_free_variables("1 + 2")
      assert MapSet.new([:a]) === get_free_variables("a + 2")
      assert MapSet.new([:a, :b]) === get_free_variables("a + b")
      assert MapSet.new([:a, :b, :c]) === get_free_variables("a + b + c")
      assert MapSet.new([:a, :b, :c]) === get_free_variables("a + b * c")
      assert MapSet.new([:a, :c]) === get_free_variables("a + b c")
      assert MapSet.new([:a, :c]) === get_free_variables("a + b(c)")
    end

    test "=" do
      assert MapSet.new([:b]) === get_free_variables("a = b")
      assert MapSet.new([:a, :b]) === get_free_variables("a = a + b")
      assert MapSet.new([:c]) === get_free_variables("a = b = c")
    end

    test "string interpolation" do
      assert MapSet.new([]) === get_free_variables(~S|"#{nil}"|)
      assert MapSet.new([:a]) === get_free_variables(~S|"#{a}"|)
      assert MapSet.new([:a]) === get_free_variables(~S|"#{a} b"|)
      assert MapSet.new([:a, :b]) === get_free_variables(~S|"#{a} #{b}"|)
    end

    test "binary" do
      assert MapSet.new([]) === get_free_variables(~S|<<int::integer-signed>> = <<-100>>|)
      assert MapSet.new([:int]) === get_free_variables(~S|<<int::integer-signed>>|)
    end

    test "fn -> end" do
      assert MapSet.new([]) ===
               get_free_variables("fun = fn a, b, c -> a + b * c end")

      assert MapSet.new([:d]) ===
               get_free_variables("""
               fun = fn a, b, c -> a + b * c + d end
               """)

      assert MapSet.new([:a, :b, :c, :d]) ===
               get_free_variables("""
               fun = fn a, b, c -> a + b * c + d end
               fun.(a, b, c)
               """)
    end

    test "fn -> end with guards" do
      assert MapSet.new([:b]) ===
               get_free_variables("""
               fun = fn a when a > 1 -> a end
               fun.(b)
               """)

      assert MapSet.new([:a, :b]) ===
               get_free_variables("""
               fun = fn a when a > b -> a end
               fun.(a)
               """)

      assert MapSet.new([:a, :b, :c]) ===
               get_free_variables("""
               fun = fn a when a > b -> a + b + c end
               fun.(a)
               """)

      assert MapSet.new([:a, :b, :c]) ===
               get_free_variables("""
               fun = fn a when a > b or a === b or a < b -> a + b + c end
               fun.(a)
               """)

      assert MapSet.new([:a, :b, :c]) ===
               get_free_variables("""
               fun = fn a when a > b when a === b when a < b -> a + b + c end
               fun.(a)
               """)

      assert MapSet.new([]) ===
               get_free_variables("""
               fun = fn a, b, c when a > b when a === b when a < b -> a + b + c end
               fun.(1, 2, 3)
               """)
    end

    test "function capture" do
      assert MapSet.new([:a, :b]) ===
               get_free_variables("""
               foo = fn a, c -> a + c end
               foo.(a + b)
               """)

      assert MapSet.new([:foo, :a, :b]) ===
               get_free_variables("""
               foo.(a + b)
               """)

      assert MapSet.new([:foo, :a]) ===
               get_free_variables("""
               foo.(a == 1)
               """)

      assert MapSet.new([:foo]) ===
               get_free_variables("""
               foo.(a = 1)
               """)
    end

    test "for" do
      assert MapSet.new([:b]) ===
               get_free_variables("""
               for a <- [1, 2, 3], do: a + b
               """)

      assert MapSet.new([]) ===
               get_free_variables("""
               for a <- [1, 2, 3], a < 2, b <- [1, 2, 3], b > 2, do: a + b
               """)

      assert MapSet.new([]) ===
               get_free_variables("""
               for a when a < 2 <- [1, 2, 3], b when b > 2 when b < 4 <- [1, 2, 3], b > 2, do: a + b
               """)

      assert MapSet.new([:c]) ===
               get_free_variables("""
               for a <- [1, 2, 3], c < 2, do: a + c
               """)

      assert MapSet.new([:c]) ===
               get_free_variables("""
               for a <- [1, 2, 3], a < 2, b <- [1, 2, 3], c > 2, do: a + b + c
               """)

      assert MapSet.new([:languages]) ===
               get_free_variables("""
               for {language, parent} <- languages, grandparent = languages[parent], do: {language, grandparent}
               """)

      assert MapSet.new([]) ===
               get_free_variables("""
               languages = [elixir: :erlang, erlang: :prolog, prolog: nil]

               for {language, parent} <- languages, grandparent = languages[parent], do: {language, grandparent}
               """)

      assert MapSet.new([:sentence, :w]) ===
               get_free_variables("""
               for <<c <- sentence>>, c != w, into: "", do: <<c>>
               """)

      assert MapSet.new([:charlist, :map]) ===
               get_free_variables("""
               for <<x <- charlist>>, x in ?a..?z, reduce: map do
                 acc -> Map.update(acc, <<x>>, 1, & &1 + 1)
               end
               """)

      assert MapSet.new() ===
               get_free_variables("""
               for line <- IO.stream(), into: IO.stream() do
                String.upcase(line)
               end
               """)

      assert MapSet.new([:plan]) ===
               get_free_variables("""
               for ret when not is_nil(ret) <- [if(match?({_type, _name, _}, plan), do: 1)], do: ret
               """)
    end

    test "underscore variables" do
      assert MapSet.new([]) ===
               get_free_variables("""
               case 1 do
                 {_type, _name, _} -> true
                 _ -> false
               end
               """)

      assert MapSet.new([:b]) ===
               get_free_variables("""
               a = match?({_type, _name, _}, b)
               """)
    end

    test "pin" do
      assert MapSet.new([:a]) ===
               get_free_variables("""
               ^a
               """)

      assert MapSet.new([:a, :b]) ===
               get_free_variables("""
               ^a = b
               """)

      assert MapSet.new([:a, :d]) ===
               get_free_variables("""
               {^a, b} = c = d
               """)

      assert MapSet.new([:a, :b]) ===
               get_free_variables("""
               case b do
                 ^a -> true
                 _ -> false
               end
               """)

      assert MapSet.new([:b, :name]) ===
               get_free_variables("""
               a = match?({_type, ^name, _}, b)
               """)
    end

    test "macros" do
      assert MapSet.new([:b]) ===
               get_free_variables("""
               a = match?({_type, _name, _}, b)
               """)

      assert MapSet.new([:a, :b]) ===
               get_free_variables("""
               a = if a === true do
                 a
               else
                 b
               end
               """)

      assert MapSet.new([:a]) ===
               get_free_variables("""
               a = if a === true do
                 true
               else
                 false
               end
               """)

      assert MapSet.new([]) ===
               get_free_variables("""
               destructure([x, y, z], [1, 2, 3, 4, 5])
               """)
    end

    test "try" do
      assert MapSet.new([:a]) ===
               get_free_variables("""
               try do
                 a
               catch
                 _ -> 1
               end
               """)

      assert MapSet.new([:some_arg]) ===
               get_free_variables(~S|
                 try do
                   do_something_that_may_fail(some_arg)
                 rescue
                   ArgumentError ->
                     IO.puts("Invalid argument given")
                 catch
                   value ->
                     IO.puts("Caught #{inspect(value)}")
                 else
                   value ->
                     IO.puts("Success! The result was #{inspect(value)}")
                 after
                   IO.puts("This is printed regardless if it failed or succeeded")
                 end
               |)
    end
  end

  describe "eval/3" do
    test "works" do
      assert {:ok, 3} === Expression.eval(compile!("1 + 2"), [])
      assert {:ok, 3} === Expression.eval(compile!("a + b"), a: 1, b: 2)
    end

    test "errors" do
      assert match?(
               {:error, [exception]} when is_exception(exception, ArithmeticError),
               Expression.eval(compile!("a / 0"), a: 1)
             )

      assert match?(
               {:error, [exception]}
               when is_exception(exception, EvalDiagnostic),
               Expression.eval(compile!("a + b"), a: 1)
             )

      assert match?(
               {:error, [exception]}
               when is_exception(exception, UndefinedFunctionError),
               Expression.eval(compile!("a a "), a: 1)
             )
    end
  end

  defp get_free_variables(code) do
    assert {:ok, _ast, variables} = Expression.compile(code)
    MapSet.new(variables, &elem(&1, 0))
  end

  defp compile!(code) do
    assert {:ok, quoted, _variables} = Expression.compile(code)
    quoted
  end
end
