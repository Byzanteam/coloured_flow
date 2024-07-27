defmodule ColouredFlow.Expression.Scope do
  @moduledoc """
  A scope for quoted expressions traversal.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Variable

  @derive {Inspect, expect: [:env], optional: [:bound_vars, :free_vars, :pinned_vars]}

  typed_structor do
    field :env, Macro.Env.t(), enforce: true
    field :bound_vars, MapSet.t(Variable.name()), default: MapSet.new()
    field :free_vars, MapSet.t(Variable.name()), default: MapSet.new()
    field :pinned_vars, MapSet.t(Variable.name()), default: MapSet.new()
  end

  @spec new(Macro.Env.t() | t()) :: t()
  def new(%Macro.Env{} = env), do: struct(__MODULE__, env: env)
  def new(%__MODULE__{} = scope), do: struct(__MODULE__, env: scope.env)

  @spec new(env_or_scope :: Macro.Env.t() | t(), vars :: Keyword.t(MapSet.t(Variable.name()))) ::
          t()
  def new(env_or_scope, vars) when is_list(vars) do
    env_or_scope
    |> new()
    |> struct(vars)
  end

  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{env: env} = one, %__MODULE__{env: env} = another) do
    %__MODULE__{
      env: env,
      bound_vars: MapSet.union(one.bound_vars, another.bound_vars),
      free_vars: MapSet.union(one.free_vars, another.free_vars),
      pinned_vars: MapSet.union(one.pinned_vars, another.pinned_vars)
    }
  end
end
