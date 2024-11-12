defmodule ColouredFlow.DefinitionHelpers do
  @moduledoc false

  defmacro __using__(_opts) do
    quote generated: true do
      alias ColouredFlow.Definition.Action
      alias ColouredFlow.Definition.Arc
      alias ColouredFlow.Definition.ColouredPetriNet
      alias ColouredFlow.Definition.Constant
      alias ColouredFlow.Definition.Expression
      alias ColouredFlow.Definition.Place
      alias ColouredFlow.Definition.Transition
      alias ColouredFlow.Definition.Variable

      import ColouredFlow.Definition.Helper
    end
  end
end
