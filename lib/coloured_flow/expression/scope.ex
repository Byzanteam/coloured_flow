defmodule ColouredFlow.Expression.Scope do
  @moduledoc """
  A scope for quoted expressions traversal.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Variable

  @derive {Inspect, except: [:env], optional: [:bound_vars, :free_vars, :pinned_vars]}

  @typep var_position() :: [line: pos_integer(), column: pos_integer()]
  @type vars() :: %{Variable.name() => [var_position()]}

  typed_structor do
    field :env, Macro.Env.t(), enforce: true
    field :bound_vars, vars(), default: %{}
    field :free_vars, vars(), default: %{}
    field :pinned_vars, vars(), default: %{}
  end

  @doc """
  Creates a new scope.

  ## Examples

      iex> env = __ENV__
      iex> scope = ColouredFlow.Expression.Scope.new(env)
      %ColouredFlow.Expression.Scope{
        env: env,
        bound_vars: %{},
        free_vars: %{},
        pinned_vars: %{}
      }
      iex>  ColouredFlow.Expression.Scope.new(scope)
      %ColouredFlow.Expression.Scope{
        env: env,
        bound_vars: %{},
        free_vars: %{},
        pinned_vars: %{}
      }
  """
  @spec new(Macro.Env.t() | t()) :: t()
  def new(%Macro.Env{} = env), do: struct(__MODULE__, env: env)
  def new(%__MODULE__{} = scope), do: struct(__MODULE__, env: scope.env)

  @spec new(
          env_or_scope :: Macro.Env.t() | t(),
          vars :: [{:bound_vars | :free_vars | :pinned_vars, vars()}]
        ) :: t()
  def new(env_or_scope, vars) when is_list(vars) do
    env_or_scope
    |> new()
    |> struct(vars)
  end

  @doc """
  Merges two scopes, concatenating their variables.

  ## Examples

      iex> env = __ENV__
      iex> scope1 = ColouredFlow.Expression.Scope.new(env, bound_vars: %{a: [[line: 1, column: 1]]})
      iex> scope2 = ColouredFlow.Expression.Scope.new(env, bound_vars: %{a: [[line: 1, column: 2]]})
      iex> ColouredFlow.Expression.Scope.merge(scope1, scope2)
      %ColouredFlow.Expression.Scope{
        env: env,
        bound_vars: %{a: [[line: 1, column: 1], [line: 1, column: 2]]},
        free_vars: %{},
        pinned_vars: %{}
      }
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{env: env} = one, %__MODULE__{env: env} = another) do
    %__MODULE__{
      env: env,
      bound_vars: merge_vars(one.bound_vars, another.bound_vars),
      free_vars: merge_vars(one.free_vars, another.free_vars),
      pinned_vars: merge_vars(one.pinned_vars, another.pinned_vars)
    }
  end

  @doc """
  Merges two sets of variables, concatenating their positions.

  ## Examples

      iex> ColouredFlow.Expression.Scope.merge_vars(%{a: [[line: 1, column: 1]]}, %{a: [[line: 1, column: 2]]})
      %{a: [[line: 1, column: 1], [line: 1, column: 2]]}

      iex> ColouredFlow.Expression.Scope.merge_vars(%{a: [[line: 1, column: 1]]}, %{a: [[line: 1, column: 2], [line: 1, column: 1]]})
      %{a: [[line: 1, column: 1], [line: 1, column: 2]]}
  """
  @spec merge_vars(vars(), vars()) :: vars()
  def merge_vars(vars1, vars2) do
    Map.merge(vars1, vars2, fn _name, pos1, pos2 ->
      pos1 |> Stream.concat(pos2) |> Enum.uniq()
    end)
  end

  @doc """
  Drops variables from the scope.

  ## Examples

      iex> scope = ColouredFlow.Expression.Scope.new(__ENV__, bound_vars: %{a: [[line: 1, column: 1]]})
      iex> ColouredFlow.Expression.Scope.drop_vars(scope.bound_vars, %{a: [[line: 1, column: 1]]})
      %{}

      iex> scope = ColouredFlow.Expression.Scope.new(__ENV__, bound_vars: %{a: [[line: 1, column: 1], [line: 1, column: 2]]})
      iex> ColouredFlow.Expression.Scope.drop_vars(scope.bound_vars, %{a: nil, b: [line: 1, column: 1]})
      %{}
  """
  @spec drop_vars(vars(), vars()) :: vars()
  def drop_vars(vars, vars_to_drop) do
    Map.drop(vars, Map.keys(vars_to_drop))
  end

  @doc """
  Adds a variable to the scope, recording its position in the source code.

  ## Examples

      iex> scope = ColouredFlow.Expression.Scope.new(__ENV__)
      iex> ColouredFlow.Expression.Scope.put_var(scope.bound_vars, :a, [line: 1, column: 1])
      %{a: [[line: 1, column: 1]]}

      iex> scope = ColouredFlow.Expression.Scope.new(__ENV__, bound_vars: %{a: [[line: 1, column: 1]]})
      iex> ColouredFlow.Expression.Scope.put_var(scope.bound_vars, :a, [line: 1, column: 2])
      %{a: [[line: 1, column: 1], [line: 1, column: 2]]}
  """
  @spec put_var(vars(), Variable.name(), var_position()) :: vars()
  def put_var(vars, name, meta) do
    pos = Keyword.take(meta, [:line, :column])
    Map.update(vars, name, [pos], &Enum.concat(&1, [pos]))
  end

  @doc """
  Checks if a variable is present in the scope.

  ## Examples

      iex> scope = ColouredFlow.Expression.Scope.new(__ENV__)
      iex> ColouredFlow.Expression.Scope.has_var?(scope.bound_vars, :a)
      false

      iex> scope = ColouredFlow.Expression.Scope.new(__ENV__, bound_vars: %{a: [[line: 1, column: 1]]})
      iex> ColouredFlow.Expression.Scope.has_var?(scope.bound_vars, :a)
      true
  """
  @spec has_var?(vars(), Variable.name()) :: boolean()
  def has_var?(vars, name), do: Map.has_key?(vars, name)
end
