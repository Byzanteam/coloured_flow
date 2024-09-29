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
          {:ok, Workitem.t(:allocated)} | {:error, Exception.t()}
  def allocate_workitem(enactment_id, workitem_id) do
    case allocate_workitems(enactment_id, [workitem_id]) do
      {:ok, [workitem]} -> {:ok, workitem}
      {:error, exception} -> {:error, exception}
    end
  end

  @spec allocate_workitems(enactment_id(), [workitem_id()]) ::
          {:ok, [Workitem.t(:allocated)]} | {:error, Exception.t()}
  def allocate_workitems(enactment_id, workitem_ids) when is_list(workitem_ids) do
    enactment = via_name(enactment_id)

    GenServer.call(enactment, {:allocate_workitems, workitem_ids})
  end

  defp via_name(enactment_id) do
    Registry.via_name({:enactment, enactment_id})
  end
end
