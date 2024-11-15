defmodule ColouredFlow.Expression.Env do
  @moduledoc """
  The Macro.Env for evaluating expressions.
  """

  @doc """
  Creates a Macro.Env for evaluating expressions.

  ## Env

  1. `import ColouredFlow.Expression.Arc, only: [bind: 1]`
  2. `import ColouredFlow.MultiSet, only: :macros`
  3. `import ColouredFlow.MultiSet, only: :sigils`
  """
  @spec make_env() :: Macro.Env.t()
  def make_env do
    import ColouredFlow.Expression.Arc, only: [bind: 1], warn: false
    import ColouredFlow.MultiSet, only: :macros, warn: false
    import ColouredFlow.MultiSet, only: :sigils, warn: false

    __ENV__
  end
end
