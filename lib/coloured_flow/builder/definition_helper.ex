defmodule ColouredFlow.Builder.DefinitionHelper do
  @moduledoc """
  Helper functions for building ColouredFlow definitions.
  """

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  @typep transition_arc_param() ::
           {:label, Arc.label()}
           | {:place, Place.name()}
           | {:orientation, Arc.orientation()}
           | {:expression, binary()}

  @typep action_param() ::
           {:payload, binary()}
           | {:outputs, [Variable.name()]}

  @spec build_arc!([{:transition, Transition.name()} | transition_arc_param()]) :: Arc.t()
  def build_arc!(params) do
    params = Keyword.validate!(params, [:label, :place, :transition, :orientation, :expression])
    expr = Arc.build_expression!(params[:orientation], params[:expression])

    struct!(
      Arc,
      params
      |> Keyword.take([:label, :place, :transition, :orientation])
      |> Keyword.merge(expression: expr)
    )
  end

  @spec build_transition_arcs!(
          transition :: Transition.name(),
          params_list :: [[transition_arc_param()]]
        ) :: [Arc.t()]
  def build_transition_arcs!(transition, params_list) when is_list(params_list) do
    Enum.map(params_list, fn params ->
      build_arc!([{:transition, transition} | params])
    end)
  end

  @spec build_action!([action_param()]) :: Action.t()
  def build_action!(params) do
    params = Keyword.validate!(params, [:payload, :outputs])

    struct!(Action, params)
  end

  @spec build_transition!(name: Transition.name(), guard: binary(), action: [action_param()]) ::
          Transition.t()
  def build_transition!(params) do
    params =
      params
      |> Keyword.validate!([:name, :guard, :action])
      |> Keyword.update(:guard, nil, &Expression.build!/1)
      |> Keyword.update(:action, %Action{}, &build_action!/1)

    struct!(Transition, params)
  end

  @doc """
  Use arc macro to define an arc between a transition and a place.

  ### Examples

  #### Define a place and a transition
  ```elixir
  arc turn_green_ew <~ red_ew :: "bind {1, u}"
  ```
  is equal to the following code:
  ```elixir
  build_arc!(
    place: "red_ew",
    transition: "turn_green_ew",
    orientation: :p_to_t,
    expression: "bind {1, u}"
  )
  ```

  #### Define a transition to a place
  ```elixir
  arc turn_green_ew ~> green_ew :: "{1, u}"
  ```
  is equal to the following code:
  ```elixir
  build_arc!(
    place: "green_ew",
    transition: "turn_green_ew",
    orientation: :t_to_p,
    expression: "{1, u}"
  )
  ```
  """
  defmacro arc({:"::", _meta, [{op, _op_meta, [transition, place]}, expression]})
           when op in [:~>, :<~] do
    orientation =
      case op do
        :~> -> :t_to_p
        :<~ -> :p_to_t
      end

    quote do
      build_arc!(
        place: unquote(var_to_string(place)),
        transition: unquote(var_to_string(transition)),
        orientation: unquote(orientation),
        expression: unquote(expression)
      )
    end
  end

  defp var_to_string({name, _meta, context}) when is_atom(name) and is_atom(context) do
    Atom.to_string(name)
  end

  defp var_to_string({name, _meta, context} = var) when is_atom(name) and is_atom(context) do
    raise """
    Expected a variable name, got #{inspect(var)}
    """
  end
end
