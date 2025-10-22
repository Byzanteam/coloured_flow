defmodule ColouredFlow.Definition.Transition do
  @moduledoc """
  Transition t is enabled at a binding if there are tokens matching the values of
  the in-coming arc inscriptions and the guard of t evaluates to true.

  ## Substitution Transitions

  A transition can be a substitution transition, which means it references a module.
  When a substitution transition fires, it instantiates and executes the referenced module.
  The module's port places are connected to the parent net's places through socket assignments.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Expression
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.SocketAssignment

  @type name() :: binary()

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    field :name, name(), enforce: true

    field :guard, Expression.t(),
      doc: """
      The guard of the transition.
      If not specified, the transition is always enabled.

      Note that, the guard can't refer to an unbound variable,
      it can only refer to variables from incoming arcs or constants.

      If the guard is `nil`, the transition is always enabled.
      However, if the guard code is `""`, the transition is never enabled.
      See `ColouredFlow.Definition.Expression.build/1` for more details.
      """

    field :action, Action.t(),
      enforce: true,
      doc: """
      The action to be executed when the transition is fired,
      you can utilize it to do side effects,
      and update unbonud variables in the out-going arcs.
      """

    field :subst, Module.name(),
      enforce: false,
      doc: """
      If present, this transition is a substitution transition that references a module.
      When fired, the module will be instantiated and executed.
      """

    field :socket_assignments, [SocketAssignment.t()],
      enforce: false,
      default: [],
      doc: """
      Socket assignments map places in the parent net to port places in the referenced module.
      Only relevant for substitution transitions (when `subst` is not nil).
      """
  end

  @doc """
  Checks if this transition is a substitution transition.
  """
  @spec substitution?(t()) :: boolean()
  def substitution?(%__MODULE__{subst: subst}), do: not is_nil(subst)

  @doc """
  Checks if this transition is a regular (non-substitution) transition.
  """
  @spec regular?(t()) :: boolean()
  def regular?(transition), do: not substitution?(transition)
end
