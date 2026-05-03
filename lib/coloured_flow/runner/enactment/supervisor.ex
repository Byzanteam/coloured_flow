defmodule ColouredFlow.Runner.Enactment.Supervisor do
  @moduledoc """
  The dynamic supervisor to manage the enactment processes.
  """

  use DynamicSupervisor

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Storage

  @typep enactment_id() :: Storage.enactment_id()

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @type start_option() ::
          {:lifecycle_hooks, ColouredFlow.Runner.Enactment.LifecycleHooks.t()}
          | {:timeout, timeout()}
          | {:hibernate_after, timeout()}

  @doc """
  Start an enactment process under the dynamic supervisor.

  Accepts the same lifecycle options as
  `ColouredFlow.Runner.Enactment.start_link/1`. Notably, `:lifecycle_hooks`
  registers a per-instance `ColouredFlow.Runner.Enactment.LifecycleHooks` module.
  The accepted shapes are `module()`, `{module(), keyword()}`, or `nil`; a bare
  module is normalised to `{module, []}` by `Enactment.start_link/1`. When
  omitted, no hooks are invoked and the enactment behaves exactly as before. A
  malformed value raises `ArgumentError` from `Enactment.start_link/1`.
  """
  @spec start_enactment(enactment_id(), [start_option()]) :: DynamicSupervisor.on_start_child()
  def start_enactment(enactment_id, options \\ []) when is_list(options) do
    enactment_spec = {Enactment, Keyword.put(options, :enactment_id, enactment_id)}

    case DynamicSupervisor.start_child(__MODULE__, enactment_spec) do
      {:ok, _pid} = ok -> ok
      {:error, {:already_started, pid}} -> {:ok, pid}
      otherwise -> otherwise
    end
  end

  @doc """
  Terminate an enactment forcibly.
  """
  @spec terminate_enactment(enactment_id(), options :: [message: String.t()]) :: :ok
  def terminate_enactment(enactment_id, options \\ []) do
    enactment = Registry.via_name({:enactment, enactment_id})

    GenServer.call(enactment, {:terminate, options})
  end
end
