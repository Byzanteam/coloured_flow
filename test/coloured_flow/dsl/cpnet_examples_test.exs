defmodule ColouredFlow.DSL.CpnetExamplesTest do
  @moduledoc """
  Each `:sample_cpn` from `ColouredFlow.CpnetBuilder` is reproduced via the DSL
  and compared structurally against the builder output.
  """

  use ExUnit.Case, async: true

  alias ColouredFlow.Definition.ColouredPetriNet

  defmodule SimpleSequenceDSL do
    use ColouredFlow.DSL

    colset int() :: integer()

    var x :: int()

    place(:input, :int)
    place(:output, :int)

    transition :pass_through do
      input(:input, bind({1, x}), label: "in")
      output(:output, {1, x}, label: "out")
    end
  end

  defmodule DeferredChoiceDSL do
    use ColouredFlow.DSL

    colset int() :: integer()

    var x :: int()

    place(:input, :int)
    place(:place, :int)
    place(:output_1, :int)
    place(:output_2, :int)

    transition :pass_through do
      input(:input, bind({1, x}))
      output(:place, {1, x})
    end

    transition :deferred_choice_1 do
      input(:place, bind({1, x}))
      output(:output_1, {1, x})
    end

    transition :deferred_choice_2 do
      input(:place, bind({1, x}))
      output(:output_2, {1, x})
    end
  end

  defmodule ParallelSplitDSL do
    use ColouredFlow.DSL

    colset int() :: integer()

    var x :: int()

    place(:input, :int)
    place(:place_1, :int)
    place(:place_2, :int)
    place(:output_1, :int)
    place(:output_2, :int)

    transition :parallel_split do
      input(:input, bind({1, x}))
      output(:place_1, {1, x})
      output(:place_2, {1, x})
    end

    transition :pass_through_1 do
      input(:place_1, bind({1, x}))
      output(:output_1, {1, x})
    end

    transition :pass_through_2 do
      input(:place_2, bind({1, x}))
      output(:output_2, {1, x})
    end
  end

  defmodule GeneralizedAndJoinDSL do
    use ColouredFlow.DSL

    colset int() :: integer()

    var x :: int()

    place(:input1, :int)
    place(:input2, :int)
    place(:input3, :int)
    place(:output, :int)

    transition :and_join do
      input(:input1, bind({1, x}), label: "input1")
      input(:input2, bind({1, x}), label: "input2")
      input(:input3, bind({1, x}), label: "input3")

      output(:output, {1, x}, label: "output")
    end
  end

  defmodule ThreadMergeDSL do
    use ColouredFlow.DSL

    colset int() :: integer()

    var x :: int()

    place(:input, :int)
    place(:merge, :int)
    place(:output, :int)

    transition :branch_1 do
      input(:input, bind({1, x}))
      output(:merge, {1, x})
    end

    transition :branch_2 do
      input(:input, bind({1, x}))
      output(:merge, {1, x})
    end

    transition :thread_merge do
      input(:merge, bind({2, 1}))
      output(:output, {1, 1})
    end
  end

  defmodule TransmissionProtocolDSL do
    use ColouredFlow.DSL

    colset no() :: integer()
    colset data() :: binary()
    colset no_data() :: {integer(), binary()}
    colset bool() :: boolean()

    var n :: no()
    var k :: no()
    var d :: data()
    var data :: data()
    var success :: bool()

    place(:packets_to_send, :no_data)
    place(:a, :no_data)
    place(:b, :no_data)
    place(:data_recevied, :data)
    place(:next_rec, :no)
    place(:c, :no)
    place(:d, :no)
    place(:next_send, :no)

    transition :send_packet do
      input(:packets_to_send, bind({1, {n, d}}))
      input(:next_send, bind({1, {1, n}}))

      output(:packets_to_send, {1, {n, d}})
      output(:a, {1, {n, d}})
      output(:next_send, {1, {1, n}})
    end

    transition :transmit_packet do
      input(:a, bind({1, {n, d}}))

      output(:b, if(success, do: {1, {n, d}}, else: {0, {n, d}}))
    end

    transition :receive_packet do
      input(:b, bind({1, {n, d}}))
      input(:data_recevied, bind({1, data}))
      input(:next_rec, bind({1, k}))

      output(:data_recevied, if(n == k, do: {1, data <> d}, else: {1, data}))
      output(:c, if(n == k, do: {1, k + 1}, else: {1, k}))
      output(:next_rec, if(n == k, do: {1, k + 1}, else: {1, k}))
    end

    transition :transmit_ack do
      input(:c, bind({1, n}))

      output(:d, if(success, do: {1, n}, else: {0, n}))
    end

    transition :receive_ack do
      input(:next_send, bind({1, k}))
      input(:d, bind({1, n}))

      output(:next_send, {1, n})
    end
  end

  describe "DSL produces the same cpnet as the builder" do
    test "simple_sequence", do: assert_equivalent(:simple_sequence, SimpleSequenceDSL)
    test "deferred_choice", do: assert_equivalent(:deferred_choice, DeferredChoiceDSL)
    test "parallel_split", do: assert_equivalent(:parallel_split, ParallelSplitDSL)

    test "generalized_and_join",
      do: assert_equivalent(:generalized_and_join, GeneralizedAndJoinDSL)

    test "thread_merge", do: assert_equivalent(:thread_merge, ThreadMergeDSL)

    test "transmission_protocol",
      do: assert_equivalent(:transmission_protocol, TransmissionProtocolDSL)
  end

  defp assert_equivalent(name, mod) do
    # Apply the same high-level build pipeline (currently `SetActionOutputs`)
    # the DSL runs, so action outputs computed from arc free-vars line up.
    expected = name |> ColouredFlow.CpnetBuilder.build_cpnet() |> ColouredFlow.Builder.build()
    actual = mod.cpnet()
    assert normalize(actual) == normalize(expected)
  end

  defp normalize(%ColouredPetriNet{} = cpnet) do
    %ColouredPetriNet{
      cpnet
      | colour_sets: Enum.sort_by(cpnet.colour_sets, & &1.name),
        places: Enum.sort_by(cpnet.places, & &1.name),
        transitions:
          cpnet.transitions
          |> Enum.map(&normalize_transition/1)
          |> Enum.sort_by(& &1.name),
        arcs:
          cpnet.arcs
          |> Enum.map(&normalize_arc/1)
          |> Enum.sort_by(&arc_key/1),
        variables: Enum.sort_by(cpnet.variables, & &1.name),
        constants: Enum.sort_by(cpnet.constants, & &1.name),
        functions:
          cpnet.functions
          |> Enum.map(&normalize_procedure/1)
          |> Enum.sort_by(& &1.name)
    }
  end

  defp normalize_transition(transition) do
    %{transition | guard: normalize_expression(transition.guard)}
  end

  defp normalize_arc(arc) do
    %{arc | expression: normalize_expression(arc.expression)}
  end

  defp normalize_procedure(procedure) do
    %{procedure | expression: normalize_expression(procedure.expression)}
  end

  # The `code` field is a human-readable rendering of the AST and depends on
  # how the AST was originally written. Two functionally identical
  # expressions can have different `code` strings (e.g. `bind {1, x}` vs
  # `bind({1, x})`). The semantic content lives in `vars` plus the parsed
  # AST, so we drop `code` and the meta-line/column info from `expr` for
  # comparison purposes.
  defp normalize_expression(nil), do: nil

  defp normalize_expression(%{code: _code, expr: expr, vars: vars} = expression) do
    %{expression | code: nil, expr: scrub_meta(expr), vars: vars}
  end

  defp scrub_meta(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} -> {form, [], args}
      other -> other
    end)
  end

  defp arc_key(arc) do
    {arc.transition, arc.orientation, arc.place, arc.label || ""}
  end
end
