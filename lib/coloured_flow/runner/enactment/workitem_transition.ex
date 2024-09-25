defmodule ColouredFlow.Runner.Enactment.WorkitemTransition do
  @moduledoc """
  Workitem transition functions, which are dispatched to the corresponding enactment gen_server.
  """

  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage

  @typep enactment_id() :: Storage.enactment_id()
  @typep workitem_id() :: Workitem.id()

  @spec allocate_workitem(enactment_id(), workitem_id()) ::
          {:ok, Workitem.t()} | {:error, Exception.t()}
  def allocate_workitem(enactment_id, workitem_id) do
    enactment = via_name(enactment_id)

    GenServer.call(enactment, {:allocate_workitem, workitem_id})
  end

  defp via_name(enactment_id) do
    Registry.via_name({:enactment, enactment_id})
  end
end
