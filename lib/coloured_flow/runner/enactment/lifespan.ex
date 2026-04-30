defmodule ColouredFlow.Runner.Enactment.Lifespan do
  @moduledoc """
  The lifespan of a `ColouredFlow.Runner.Enactment` GenServer can be configured
  through the config. Two knobs are exposed:

  - `:timeout` — how long the process may sit idle before it shuts itself down.
    Defaults to `:infinity` (the enactment is long-lived).
  - `:hibernate_after` — how long the process may sit idle before BEAM moves its
    state into hibernation, compressing memory at the cost of a small wake-up
    latency on the next message. Defaults to `15_000` ms.

  Both values follow the same precedence: per-`enactment` option (passed to
  `ColouredFlow.Runner.Enactment.start_link/1`) overrides application config,
  which in turn overrides the built-in default.

  Example:

  ```elixir
  config :coloured_flow,
         ColouredFlow.Runner.Enactment,
         timeout: 60 * 1000,           # 1 minute
         hibernate_after: 15 * 1000    # 15 seconds
  ```

  > #### `:timeout` shadows `:hibernate_after` {: .info}
  >
  > Per OTP `gen_server` semantics, `:hibernate_after` only takes effect when the
  > GenServer's `noreply` timeout is `:infinity`. With a finite `:timeout`, BEAM
  > uses that as the receive timeout (which fires the inactivity-shutdown path)
  > and ignores `:hibernate_after`. Hibernation is therefore most useful with the
  > default `:timeout` of `:infinity`.
  """

  alias ColouredFlow.Runner.Enactment

  @default_timeout :infinity
  @default_hibernate_after 15_000

  @spec timeout(Enactment.state()) :: timeout()
  def timeout(%Enactment{timeout: nil}) do
    fetch_env(:timeout, @default_timeout)
  end

  def timeout(%Enactment{timeout: timeout}), do: timeout

  @doc """
  Resolves the `:hibernate_after` value for a running enactment, falling back to
  application config and the built-in default when no per-enactment value was
  supplied.
  """
  @spec hibernate_after(Enactment.state()) :: timeout()
  def hibernate_after(%Enactment{hibernate_after: nil}) do
    fetch_env(:hibernate_after, @default_hibernate_after)
  end

  def hibernate_after(%Enactment{hibernate_after: hibernate_after}), do: hibernate_after

  @doc """
  Resolves the `:hibernate_after` value at `start_link/1` time, before the
  GenServer state struct exists. Mirrors `hibernate_after/1` but reads from the
  raw options keyword list.
  """
  @spec hibernate_after_from_options(Enactment.options()) :: timeout()
  def hibernate_after_from_options(options) when is_list(options) do
    case Keyword.get(options, :hibernate_after) do
      nil -> fetch_env(:hibernate_after, @default_hibernate_after)
      value -> value
    end
  end

  @spec fetch_env(atom(), timeout()) :: timeout()
  defp fetch_env(key, default) do
    :coloured_flow
    |> Application.get_env(ColouredFlow.Runner.Enactment, [])
    |> Keyword.get(key, default)
  end
end
