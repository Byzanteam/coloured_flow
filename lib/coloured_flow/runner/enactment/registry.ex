defmodule ColouredFlow.Runner.Enactment.Registry do
  @moduledoc false

  alias ColouredFlow.Runner.Storage

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [keys: :unique, name: __MODULE__]}
    }
  end

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec via_name({:enactment, Storage.enactment_id()}) :: {:via, Registry, term()}
  def via_name({:enactment, id}) do
    {:via, Registry, {__MODULE__, {:enactment, id}}}
  end
end
