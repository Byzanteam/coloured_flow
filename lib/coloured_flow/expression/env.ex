defmodule ColouredFlow.Expression.Env do
  @moduledoc """
  The Macro.Env for evaluating expressions.
  """

  @doc """
  Creates a Macro.Env for evaluating expressions.

  ## Env

  1. `import ColouredFlow.Expression.Arc, only: [bind: 1]`
  """
  @spec make_env() :: Macro.Env.t()
  def make_env do
    import ColouredFlow.Expression.Arc, only: [bind: 1], warn: false

    __ENV__
  end
end
