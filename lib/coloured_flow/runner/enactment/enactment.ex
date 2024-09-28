defmodule ColouredFlow.Runner.Enactment do
  @moduledoc """
  Each process instance represents one individual enactment of the process, using its
  own process instance data, and which is (normally) capable of independent control
  and audit as it progresses towards completion or termination.
  """

  use GenServer
  use TypedStructor

  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment.Catchuping
  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Enactment.WorkitemCalibration
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage

  @typep enactment_id() :: Storage.enactment_id()
  @typep workitem_id() :: Workitem.id()

  typed_structor type_name: :state, enforce: true do
    @typedoc "The state of the enactment."

    plugin TypedStructor.Plugins.DocFields

    field :enactment_id, enactment_id(), doc: "The unique identifier of this enactment."

    field :version, non_neg_integer(),
      default: 0,
      doc: "The version of the enactment, incremented on each occurrence."

    field :markings, [Marking.t()], default: [], doc: "The current markings of the enactment."
    field :workitems, [Workitem.t()], default: [], doc: "The live workitems of the enactment."
  end

  @typep init_arg() :: [enactment_id: enactment_id()]

  @spec start_link(init_arg()) :: GenServer.on_start()
  def start_link(init_arg) do
    enactment_id = Keyword.fetch!(init_arg, :enactment_id)

    GenServer.start_link(__MODULE__, init_arg,
      name: Registry.via_name({:enactment, enactment_id})
    )
  end

  @impl GenServer
  def init(init_arg) do
    state = %__MODULE__{
      enactment_id: Keyword.fetch!(init_arg, :enactment_id)
    }

    {:ok, state, {:continue, :populate_state}}
  end

  @impl GenServer
  def handle_continue(:populate_state, %__MODULE__{} = state) do
    snapshot =
      case Storage.read_enactment_snapshot(state.enactment_id) do
        {:ok, snapshot} ->
          snapshot

        :error ->
          %Snapshot{
            version: 0,
            markings: Storage.get_initial_markings(state.enactment_id)
          }
      end

    snapshot = catchup_snapshot(state.enactment_id, snapshot)
    Storage.take_enactment_snapshot(state.enactment_id, snapshot)

    workitems = Storage.list_live_workitems(state.enactment_id)

    {
      :noreply,
      %__MODULE__{
        state
        | version: snapshot.version,
          markings: snapshot.markings,
          workitems: workitems
      },
      {:continue, :calibrate_workitems}
    }
  end

  def handle_continue(:calibrate_workitems, %__MODULE__{} = state) do
    state = WorkitemCalibration.initial_calibrate(state)

    {:noreply, state}
  end

  def handle_continue(
        {:calibrate_workitems, transition, affected_workitems},
        %__MODULE__{} = state
      ) do
    calibration = WorkitemCalibration.calibrate(state, transition, affected_workitems)
    Storage.transition_workitems(calibration.to_withdraw, :withdrawn)

    {:noreply, calibration.state}
  end

  @spec catchup_snapshot(enactment_id(), Snapshot.t()) :: Snapshot.t()
  defp catchup_snapshot(enactment_id, snapshot) do
    occurrences = Storage.occurrences_stream(enactment_id, snapshot.version)

    {steps, markings} = Catchuping.apply(snapshot.markings, occurrences)

    %Snapshot{snapshot | version: snapshot.version + steps, markings: markings}
  end

  @impl GenServer
  def handle_call({:allocate_workitem, workitem_id}, _from, %__MODULE__{} = state) do
    case pop_workitem(state, workitem_id, :enabled) do
      {:ok, workitem, workitems} ->
        allocated_workitem = Storage.transition_workitem(workitem, :allocated)
        state = %__MODULE__{state | workitems: [allocated_workitem | workitems]}

        {:reply, {:ok, allocated_workitem}, state,
         {:continue, {:calibrate_workitems, :allocate, [workitem]}}}

      {:error, :workitem_not_found} ->
        exception =
          Exceptions.NonLiveWorkitem.exception(
            id: workitem_id,
            enactment_id: state.enactment_id
          )

        {:reply, {:error, exception}, state}

      {:error, {:workitem_unexpected_state, workitem_state}} ->
        exception =
          Exceptions.InvalidWorkitemTransition.exception(
            id: workitem_id,
            enactment_id: state.enactment_id,
            state: workitem_state,
            transition: :allocate
          )

        {:reply, {:error, exception}, state}
    end
  end

  @spec pop_workitem(state(), workitem_id(), expected_state :: Workitem.state()) ::
          {:ok, Workitem.t(), [Workitem.t()]}
          | {:error,
             :workitem_not_found | {:workitem_unexpected_state, state :: Workitem.state()}}
  defp pop_workitem(%__MODULE__{} = state, workitem_id, expected_state) do
    case Enum.split_with(state.workitems, &(&1.id === workitem_id)) do
      {[], _workitems} ->
        {:error, :workitem_not_found}

      {[%Workitem{state: ^expected_state} = workitem], workitems} ->
        {:ok, workitem, workitems}

      {[%Workitem{} = workitem], _workitems} ->
        {:error, {:workitem_unexpected_state, workitem.state}}
    end
  end
end
