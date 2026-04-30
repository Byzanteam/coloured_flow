defmodule ColouredFlow.Runner.Enactment.Registry do
  @moduledoc false

  alias ColouredFlow.Runner.Storage

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_arg) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec via_name({:enactment, Storage.enactment_id()}) :: {:via, Registry, term()}
  def via_name({:enactment, id}) do
    {:via, Registry, {__MODULE__, {:enactment, id}}}
  end

  @doc """
  Look up the pid registered under the given key, returning `{:ok, pid}` or
  `:error` if no process is registered.
  """
  @spec whereis({:enactment, Storage.enactment_id()}) :: {:ok, pid()} | :error
  def whereis({:enactment, id}) do
    case Registry.lookup(__MODULE__, {:enactment, id}) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end
end
