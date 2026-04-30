defmodule ColouredFlow.Runner.Enactment.Supervisor do
  @moduledoc """
  The dynamic supervisor to manage the enactment processes.
  """

  use DynamicSupervisor

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Enactment.WorkitemTransition
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

  @spec start_enactment(enactment_id()) :: DynamicSupervisor.on_start_child()
  def start_enactment(enactment_id) do
    enactment_spec = {Enactment, enactment_id: enactment_id}

    case DynamicSupervisor.start_child(__MODULE__, enactment_spec) do
      {:ok, _pid} = ok -> ok
      {:error, {:already_started, pid}} -> {:ok, pid}
      otherwise -> otherwise
    end
  end

  @doc """
  Terminate an enactment forcibly.

  Returns `:ok` on success, or `{:error, exception}` when the target enactment is
  not running, the call times out, or the call exits abnormally.
  """
  @spec terminate_enactment(enactment_id(), options :: [message: String.t()]) ::
          :ok | {:error, Exception.t()}
  def terminate_enactment(enactment_id, options \\ []) do
    case WorkitemTransition.call_enactment(enactment_id, {:terminate, options}) do
      :ok -> :ok
      {:error, _exception} = error -> error
    end
  end
end
