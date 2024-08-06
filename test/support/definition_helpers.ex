defmodule ColouredFlow.DefinitionHelpers do
  @moduledoc false

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  defmacro __using__(_opts) do
    quote generated: true do
      alias ColouredFlow.Definition.Action
      alias ColouredFlow.Definition.Arc
      alias ColouredFlow.Definition.ColouredPetriNet
      alias ColouredFlow.Definition.Expression
      alias ColouredFlow.Definition.Place
      alias ColouredFlow.Definition.Transition
      alias ColouredFlow.Definition.Variable

      import unquote(__MODULE__)
    end
  end

  @spec build_arc!(
          name: Arc.name(),
          place: Place.name(),
          transition: Transition.name(),
          orientation: Arc.orientation(),
          expression: binary()
        ) :: Arc.t()
  def build_arc!(params) do
    expr = Expression.build!(params[:expression])
    bindings = Arc.build_bindings!(expr)

    %Arc{
      name: params[:name],
      place: params[:place],
      transition: params[:transition],
      orientation: params[:orientation],
      expression: expr,
      bindings: bindings
    }
  end

  @spec build_action!(
          free_vars: [Variable.name()],
          code: binary()
        ) :: Action.t()
  def build_action!(params) do
    code = Expression.build!(params[:code])
    outputs = Action.build_outputs!(code)

    %Action{
      free_vars: params[:free_vars],
      outputs: outputs,
      code: code
    }
  end
end
