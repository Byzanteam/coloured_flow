defmodule ColouredFlow.Runner.Storage do
  @moduledoc """
  The Storage is responsible for storing the data that is being produced by the Runner.

  To use `ColouredFlow.Runner.Storage.Default`, you need to configure the storage module in your config.exs:

  ```elixir
  config :coloured_flow, ColouredFlow.Runner.Storage,
    repo: ColouredFlow.TestRepo,
    storage: ColouredFlow.Runner.Storage.Default
  ```
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem

  @type enactment_id() :: Ecto.UUID.t()
  @type flow_id() :: Ecto.UUID.t()

  @doc """
  Get the flow of an enactment.
  """
  @callback get_flow_by_enactment(enactment_id()) :: ColouredPetriNet.t()

  @doc """
  Returns the initial markings for the given enactment.
  """
  @callback get_initial_markings(enactment_id()) :: [Marking.t()]

  @doc """
  Returns a stream of occurrences for the given enactment,
  that occurred after the given `from`(exclusive) position.
  """
  @callback occurrences_stream(enactment_id(), from :: non_neg_integer()) ::
              Enumerable.t(Occurrence.t())

  @doc """
  Returns a list of live workitems for the given enactment.
  """
  @doc group: :workitem
  @callback list_live_workitems(enactment_id()) :: [Workitem.t(Workitem.live_state())]

  @doc """
  Produces the workitems for the given enactment.
  """
  @doc group: :workitem
  @callback produce_workitems(enactment_id(), Enumerable.t(BindingElement.t())) ::
              [Workitem.t(:enabled)]

  @doc group: :workitem
  @callback allocate_workitems([Workitem.t()]) :: [Workitem.t(:allocated)]

  @doc group: :workitem
  @callback start_workitems([Workitem.t()]) :: [Workitem.t(:started)]

  @doc group: :workitem
  @callback withdraw_workitems([Workitem.t()]) :: [Workitem.t(:withdrawn)]

  @doc group: :workitem
  @callback complete_workitems(
              enactment_id(),
              current_version :: non_neg_integer(),
              workitem_occurrences :: [{Workitem.t(:started), Occurrence.t()}]
            ) :: [Workitem.t(:completed)]

  @doc """
  Takes a snapshot of the given enactment.
  """
  @doc group: :snapshot
  @callback take_enactment_snapshot(enactment_id(), Snapshot.t()) :: :ok

  @doc """
  Reads the snapshot of the given enactment.
  """
  @doc group: :snapshot
  @callback read_enactment_snapshot(enactment_id()) :: {:ok, Snapshot.t()} | :error

  @doc false
  @spec get_flow_by_enactment(enactment_id()) :: ColouredPetriNet.t()
  def get_flow_by_enactment(enactment_id) do
    __storage__().get_flow_by_enactment(enactment_id)
  end

  @doc false
  @spec get_initial_markings(enactment_id()) :: [Marking.t()]
  def get_initial_markings(enactment_id) do
    __storage__().get_initial_markings(enactment_id)
  end

  @doc false
  @spec occurrences_stream(enactment_id(), from :: non_neg_integer()) ::
          Enumerable.t(Occurrence.t())
  def occurrences_stream(enactment_id, from) do
    __storage__().occurrences_stream(enactment_id, from)
  end

  @doc false
  @spec list_live_workitems(enactment_id()) :: [Workitem.t(Workitem.live_state())]
  def list_live_workitems(enactment_id) do
    __storage__().list_live_workitems(enactment_id)
  end

  @doc false
  @spec produce_workitems(enactment_id(), Enumerable.t(BindingElement.t())) ::
          [Workitem.t(:enabled)]
  def produce_workitems(enactment_id, binding_elements) do
    __storage__().produce_workitems(enactment_id, binding_elements)
  end

  @doc false
  @spec allocate_workitems([Workitem.t()]) :: [Workitem.t(target_state)]
        when target_state: :allocated
  def allocate_workitems(workitems) do
    __storage__().allocate_workitems(workitems)
  end

  @doc false
  @spec start_workitems([Workitem.t()]) :: [Workitem.t(:started)]
  def start_workitems(workitems) do
    __storage__().start_workitems(workitems)
  end

  @doc false
  @spec withdraw_workitems([Workitem.t()]) :: [Workitem.t(:withdrawn)]
  def withdraw_workitems(workitems) do
    __storage__().withdraw_workitems(workitems)
  end

  @doc false
  @spec complete_workitems(
          enactment_id(),
          current_version :: non_neg_integer(),
          workitem_occurrences :: [{Workitem.t(:started), Occurrence.t()}]
        ) :: [Workitem.t(:completed)]
  def complete_workitems(enactment_id, current_version, workitem_occurrences) do
    __storage__().complete_workitems(enactment_id, current_version, workitem_occurrences)
  end

  @doc false
  @spec take_enactment_snapshot(enactment_id(), Snapshot.t()) :: :ok
  def take_enactment_snapshot(enactment_id, snapshot) do
    __storage__().take_enactment_snapshot(enactment_id, snapshot)
  end

  @doc false
  @spec read_enactment_snapshot(enactment_id()) :: {:ok, Snapshot.t()} | :error
  def read_enactment_snapshot(enactment_id) do
    __storage__().read_enactment_snapshot(enactment_id)
  end

  @doc """
  Returns the storage module.
  """
  @spec __storage__() :: module()
  def __storage__ do
    Application.fetch_env!(:coloured_flow, ColouredFlow.Runner.Storage)[:storage]
  end
end
