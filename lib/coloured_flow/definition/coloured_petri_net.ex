defmodule ColouredFlow.Definition.ColouredPetriNet do
  @moduledoc """
  The petri net is consists of places, transitions, arcs.

  ## Modules

  A CPN can define reusable modules that can be instantiated through substitution transitions.
  Modules enable hierarchical composition and better organization of complex workflows.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Procedure
  alias ColouredFlow.Definition.TerminationCriteria
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  typed_structor enforce: true do
    # data types
    field :colour_sets, [ColourSet.t()]

    # modules
    field :modules, [Module.t()],
      default: [],
      doc: "Reusable module definitions that can be instantiated by substitution transitions."

    # net
    field :places, [Place.t()]
    field :transitions, [Transition.t()]
    field :arcs, [Arc.t()]

    # variables
    field :variables, [Variable.t()], default: []
    field :constants, [Constant.t()], default: []

    field :functions, [Procedure.t()], default: []

    field :termination_criteria, TerminationCriteria.t(), enforce: false
  end

  @doc """
  Gets a module by name.
  """
  @spec get_module(t(), Module.name()) :: Module.t() | nil
  def get_module(%__MODULE__{modules: modules}, name) do
    Enum.find(modules, &(&1.name == name))
  end

  @doc """
  Returns all substitution transitions in the net.
  """
  @spec substitution_transitions(t()) :: [Transition.t()]
  def substitution_transitions(%__MODULE__{transitions: transitions}) do
    Enum.filter(transitions, &Transition.substitution?/1)
  end

  @doc """
  Returns all regular (non-substitution) transitions in the net.
  """
  @spec regular_transitions(t()) :: [Transition.t()]
  def regular_transitions(%__MODULE__{transitions: transitions}) do
    Enum.filter(transitions, &Transition.regular?/1)
  end
end
