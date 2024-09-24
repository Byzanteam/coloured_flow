defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ColouredPetriNetTest do
  use ColouredFlow.Runner.CodecCase, codec: ColouredPetriNet, async: true
  use ColouredFlow.DefinitionHelpers

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Procedure

  describe "codec" do
    test "works" do
      simple_net = %ColouredPetriNet{
        colour_sets: [%ColourSet{name: :int, type: {:integer, []}}],
        places: [
          %Place{name: "integer", colour_set: :int},
          %Place{name: "even", colour_set: :int}
        ],
        transitions: [
          %Transition{name: "filter", guard: Expression.build!("Integer.mod(integer, 2) === 0")}
        ],
        arcs: [
          build_arc!(
            label: "input",
            place: "integer",
            transition: "filter",
            orientation: :p_to_t,
            expression: "bind {1, x}"
          ),
          build_arc!(
            label: "output",
            place: "even",
            transition: "filter",
            orientation: :t_to_p,
            expression: "bind {1, x}"
          )
        ],
        variables: [
          %Variable{name: :x, colour_set: :int}
        ]
      }

      nets = [
        simple_net,
        %{
          simple_net
          | constants: [
              %Constant{name: :zero, colour_set: :int, value: 0}
            ],
            functions: [
              %Procedure{
                name: :is_even,
                expression: Expression.build!("Integer.mod(x, 2) === 0"),
                result: {:boolean, []}
              }
            ]
        }
      ]

      assert_codec(nets)
    end
  end
end
