defmodule ColouredFlow.Enactment.BindingElement do
  @moduledoc """
  A binding element comprises a transition, a set of bound assignments,
  and a set of markings to be consumed while firing the transition.

  A binding element is considered enabled if:
  1. The guard of the transition is satisfied.
  2. There are sufficient tokens on the input places of the transition.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable
  alias ColouredFlow.Enactment.Marking

  @type binding() :: {Variable.name(), ColourSet.value()}

  typed_structor enfore: true do
    plugin TypedStructor.Plugins.DocFields

    field :transition, Transition.name()

    field :binding, [binding()],
      doc: """
      The binding is a list of variable assignments that are bound to
      the input places of the transition, or to the guard. The binding
      may be referred to in the action of the transition, and the
      out-going arcs of the transition.
      """

    field :to_consume, [Marking.t()],
      doc: "The markings to be consumed while firing the transition."
  end

  @doc """
  Build a new order-consistent binding element,
  where the binding is ordered by the variable name,
  and the to_consume markings are ordered by the place name.
  """
  @spec new(
          transition :: Transition.name(),
          binding :: [binding()],
          to_consume :: [Marking.t()]
        ) ::
          t()
  def new(transition, binding, to_consume) do
    %__MODULE__{
      transition: transition,
      binding: Enum.sort_by(binding, &elem(&1, 0)),
      to_consume: Enum.sort_by(to_consume, & &1.place)
    }
  end
end
