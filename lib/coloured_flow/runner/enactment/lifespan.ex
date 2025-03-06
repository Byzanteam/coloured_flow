defmodule ColouredFlow.Runner.Enactment.Lifespan do
  @moduledoc """
  The lifespan of a `ColouredFlow.Runner.Enactment` GenServer can be configured through the config.
  The default timeout is `:infinity`.

  Example:

  ```elixir
  config :coloured_flow,
          ColouredFlow.Runner.Enactment.Lifespan,
          timeout: 60 * 1000 # 1 minute
  ```
  """

  alias ColouredFlow.Runner.Enactment

  @default_timeout :infinity

  @spec timeout(Enactment.state()) :: timeout()
  def timeout(%Enactment{timeout: nil}) do
    :coloured_flow
    |> Application.get_env(ColouredFlow.Runner.Enactment, [])
    |> Keyword.get(:timeout, @default_timeout)
  end

  def timeout(%Enactment{timeout: timeout}), do: timeout
end
