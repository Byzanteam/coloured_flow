defmodule ColouredFlowDashboard.OutputSchemaBuilderTest do
  use ExUnit.Case, async: true

  alias ColouredFlowDashboard.OutputSchemaBuilder
  alias ColouredFlowDashboard.Seeds.ApprovalFlow
  alias ColouredFlowDashboard.Seeds.IncidentTriageFlow
  alias ColouredFlowDashboardWeb.Views.OutputVar

  # Pin atoms used by `:elixir` decode tests onto the BEAM so
  # `Code.string_to_quoted(_, existing_atoms_only: true)` accepts them.
  _atom_pins = [:tool_read, :approve, :running]

  describe "build/2 on ApprovalFlow (binary-only colour sets)" do
    test "resolves :approve transition to two :string slots" do
      schema = OutputSchemaBuilder.build(ApprovalFlow.cpnet(), "approve")

      assert [%OutputVar{} | _rest] = schema
      assert Enum.all?(schema, &match?(%OutputVar{kind: :string, enum_values: nil}, &1))

      names = schema |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["note", "verdict"]

      verdict = Enum.find(schema, &(&1.name == "verdict"))
      assert verdict.colour_set == "verdict_t"
      assert verdict.hint == nil
    end
  end

  describe "build/2 on IncidentTriageFlow (enum + boolean + string)" do
    test "classifies severity as :enum with sorted-source values" do
      schema = OutputSchemaBuilder.build(IncidentTriageFlow.cpnet(), "triage")

      severity = Enum.find(schema, &(&1.name == "severity"))
      assert %OutputVar{kind: :enum, colour_set: "severity_t"} = severity
      assert severity.enum_values == ["low", "medium", "high"]
    end

    test "classifies acknowledged as :boolean" do
      schema = OutputSchemaBuilder.build(IncidentTriageFlow.cpnet(), "triage")
      ack = Enum.find(schema, &(&1.name == "acknowledged"))
      assert %OutputVar{kind: :boolean, enum_values: nil} = ack
    end

    test "classifies note as :string" do
      schema = OutputSchemaBuilder.build(IncidentTriageFlow.cpnet(), "triage")
      note = Enum.find(schema, &(&1.name == "note"))
      assert %OutputVar{kind: :string, enum_values: nil} = note
    end
  end

  describe "build/2 edge cases" do
    test "nil cpnet returns []" do
      assert OutputSchemaBuilder.build(nil, "anything") == []
    end

    test "unknown transition returns []" do
      assert OutputSchemaBuilder.build(ApprovalFlow.cpnet(), "nope") == []
    end
  end

  describe "build/2 + example generation on tuple colour sets" do
    test "PiAgentFlow's think_tool surfaces tc as :elixir with a tuple example" do
      alias ColouredFlowDashboard.Seeds.PiAgentFlow

      schema = OutputSchemaBuilder.build(PiAgentFlow.cpnet(), "think_tool")
      tc = Enum.find(schema, &(&1.name == "tc"))

      assert %OutputVar{kind: :elixir, colour_set: "tool_call"} = tc
      # `tool_call :: {tool_name(), binary()}` → tool_name resolves to its
      # first enum atom (`:read`), binary to "text". The exact rendering is
      # deterministic given the descriptor walker.
      assert tc.example == ~s|{:read, "text"}|
      assert is_binary(tc.hint)
    end
  end

  describe "coerce_value/2" do
    test "parses :elixir text into an Elixir literal" do
      schema_var = %OutputVar{
        name: "x",
        colour_set: "",
        kind: :elixir,
        enum_values: nil,
        hint: nil,
        example: ":your_term"
      }

      assert {:ok, :approve} = OutputSchemaBuilder.coerce_value(schema_var, ":approve")

      assert {:ok, {:tool_read, "path"}} =
               OutputSchemaBuilder.coerce_value(schema_var, ~s({:tool_read, "path"}))

      assert {:error, {:invalid_elixir, reason}} =
               OutputSchemaBuilder.coerce_value(schema_var, ~s|IO.puts("x")|)

      assert is_binary(reason)
    end

    test "rejects non-binary :elixir input as type mismatch" do
      v = %OutputVar{
        name: "x",
        colour_set: "",
        kind: :elixir,
        enum_values: nil,
        hint: nil,
        example: ":your_term"
      }

      assert {:error, {:type_mismatch, "elixir"}} = OutputSchemaBuilder.coerce_value(v, 42)
    end

    test "accepts integers" do
      v = %OutputVar{name: "n", colour_set: "int", kind: :integer, enum_values: nil, hint: nil}
      assert {:ok, 5} = OutputSchemaBuilder.coerce_value(v, 5)
      assert {:error, {:type_mismatch, "integer"}} = OutputSchemaBuilder.coerce_value(v, "5")
    end

    test "accepts booleans" do
      v = %OutputVar{name: "b", colour_set: "b", kind: :boolean, enum_values: nil, hint: nil}
      assert {:ok, true} = OutputSchemaBuilder.coerce_value(v, true)
      assert {:error, {:type_mismatch, "boolean"}} = OutputSchemaBuilder.coerce_value(v, "true")
    end

    test "coerces enum strings to existing atoms" do
      v = %OutputVar{
        name: "s",
        colour_set: "severity_t",
        kind: :enum,
        enum_values: ["low", "medium", "high"],
        hint: nil
      }

      assert {:ok, :low} = OutputSchemaBuilder.coerce_value(v, "low")
      assert {:error, {:unknown_enum, "extreme"}} = OutputSchemaBuilder.coerce_value(v, "extreme")
    end

    test "rejects non-binary enum input" do
      v = %OutputVar{
        name: "s",
        colour_set: "severity_t",
        kind: :enum,
        enum_values: ["low"],
        hint: nil
      }

      assert {:error, {:type_mismatch, "enum"}} = OutputSchemaBuilder.coerce_value(v, 1)
    end

    test "string kind accepts binary verbatim" do
      v = %OutputVar{name: "s", colour_set: "s", kind: :string, enum_values: nil, hint: nil}
      assert {:ok, "hi"} = OutputSchemaBuilder.coerce_value(v, "hi")
      assert {:error, {:type_mismatch, "string"}} = OutputSchemaBuilder.coerce_value(v, 1)
    end

    test "nil schema entry passes value through (free-text fallback)" do
      assert {:ok, "anything"} = OutputSchemaBuilder.coerce_value(nil, "anything")
    end
  end
end
