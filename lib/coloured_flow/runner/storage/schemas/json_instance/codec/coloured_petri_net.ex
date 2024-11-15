defmodule ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec.ColouredPetriNet do
  @moduledoc false

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Variable

  use ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec,
    codec_spec: {
      :struct,
      ColouredPetriNet,
      [
        colour_sets: {:list, {:codec, Codec.ColourSet}},
        places: {:list, {:struct, Place, [name: :string, colour_set: :atom]}},
        transitions: {:list, {:codec, Codec.Transition}},
        arcs: {:list, {:codec, Codec.Arc}},
        variables: {:list, {:struct, Variable, [name: :atom, colour_set: :atom]}},
        constants:
          {:list,
           {
             :struct,
             Constant,
             [
               name: :atom,
               colour_set: :atom,
               value: Codec.ColourSet.value_codec_spec()
             ]
           }},
        functions: {:list, {:codec, Codec.Procedure}},
        termination_criteria: {:codec, Codec.TerminationCriteria}
      ]
    }
end
