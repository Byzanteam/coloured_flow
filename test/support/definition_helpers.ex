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
          label: Arc.label(),
          place: Place.name(),
          transition: Transition.name(),
          orientation: Arc.orientation(),
          expression: binary()
        ) :: Arc.t()
  def build_arc!(params) do
    params = Keyword.validate!(params, [:label, :place, :transition, :orientation, :expression])
    expr = Expression.build!(params[:expression])

    bindings =
      case params[:orientation] do
        :p_to_t -> Arc.build_bindings!(expr)
        :t_to_p -> []
      end

    %Arc{
      label: Keyword.get(params, :label),
      place: params[:place],
      transition: params[:transition],
      orientation: params[:orientation],
      expression: expr,
      bindings: bindings
    }
  end

  @spec build_transition_arcs!(
          transition :: Transition.name(),
          params_list :: [
            label: Arc.label(),
            place: Place.name(),
            transition: Transition.name(),
            orientation: Arc.orientation(),
            expression: binary()
          ]
        ) :: [Arc.t()]
  def build_transition_arcs!(transition, params_list) do
    Enum.map(params_list, fn params ->
      build_arc!([{:transition, transition} | params])
    end)
  end

  @spec build_action!(
          code: binary(),
          inputs: [Variable.name()],
          outputs: [Variable.name()]
        ) :: Action.t()
  def build_action!(params) do
    params =
      params
      |> Keyword.validate!([:code, :inputs, :outputs])
      |> Keyword.update!(:code, &Expression.build!/1)

    struct!(Action, params)
  end

  @spec build_transition!(
          name: Transition.name(),
          guard: binary(),
          action: Action.t()
        ) :: Transition.t()
  def build_transition!(params) do
    params =
      params
      |> Keyword.validate!([:name, :guard, :action])
      |> Keyword.update(:guard, nil, &Expression.build!/1)
      |> Keyword.update(:action, nil, &build_action!/1)

    struct!(Transition, params)
  end
end
