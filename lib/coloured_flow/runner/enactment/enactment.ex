defmodule ColouredFlow.Runner.Enactment do
  @moduledoc """
  Each process instance represents one individual enactment of the process, using its
  own process instance data, and which is (normally) capable of independent control
  and audit as it progresses towards completion or termination.
  """

  use GenServer
  use TypedStructor

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment.Catchuping
  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Enactment.WorkitemCalibration
  alias ColouredFlow.Runner.Enactment.WorkitemConsumption
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage

  @typep enactment_id() :: Storage.enactment_id()

  @type markings() :: %{Place.name() => Marking.t()}
  @type workitems() :: %{Workitem.id() => Workitem.t()}

  typed_structor type_name: :state, enforce: true do
    @typedoc "The state of the enactment."

    plugin TypedStructor.Plugins.DocFields

    field :enactment_id, enactment_id(), doc: "The unique identifier of this enactment."

    field :version, non_neg_integer(),
      default: 0,
      doc: "The version of the enactment, incremented on each occurrence."

    field :markings, markings(), default: %{}, doc: "The current markings of the enactment."
    field :workitems, workitems(), default: %{}, doc: "The live workitems of the enactment."
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
          markings: Map.new(snapshot.markings, &{&1.place, &1}),
          workitems: Map.new(workitems, &{&1.id, &1})
      },
      {:continue, :calibrate_workitems}
    }
  end

  def handle_continue(:calibrate_workitems, %__MODULE__{} = state) do
    cpnet = Storage.get_flow_by_enactment(state.enactment_id)
    calibration = WorkitemCalibration.initial_calibrate(state, cpnet)
    state = apply_calibration(calibration)

    {:noreply, state}
  end

  def handle_continue(
        {:calibrate_workitems, transition, affected_workitems},
        %__MODULE__{} = state
      ) do
    calibration = WorkitemCalibration.calibrate(state, transition, affected_workitems)
    state = apply_calibration(calibration)

    {:noreply, state}
  end

  @spec catchup_snapshot(enactment_id(), Snapshot.t()) :: Snapshot.t()
  defp catchup_snapshot(enactment_id, snapshot) do
    occurrences = Storage.occurrences_stream(enactment_id, snapshot.version)

    {steps, markings} = Catchuping.apply(snapshot.markings, occurrences)

    %Snapshot{snapshot | version: snapshot.version + steps, markings: markings}
  end

  defp apply_calibration(%WorkitemCalibration{state: %__MODULE__{} = state} = calibration) do
    Storage.transition_workitems(calibration.to_withdraw, :withdrawn)

    produced_workitems =
      state.enactment_id
      |> Storage.produce_workitems(calibration.to_produce)
      |> Map.new(&{&1.id, &1})

    %__MODULE__{state | workitems: Map.merge(state.workitems, produced_workitems)}
  end

  @impl GenServer
  def handle_call({:allocate_workitems, workitem_ids}, _from, %__MODULE__{} = state)
      when is_list(workitem_ids) do
    with(
      {:ok, enabled_workitems, workitems} <-
        pop_workitems(state, workitem_ids, :allocate, :enabled),
      enabled_workitems = Map.values(enabled_workitems),
      binding_elements = Enum.map(enabled_workitems, & &1.binding_element),
      {:ok, _markings} <- WorkitemConsumption.consume_tokens(state.markings, binding_elements)
    ) do
      allocated_workitems = Storage.transition_workitems(enabled_workitems, :allocated)

      state = %__MODULE__{
        state
        | workitems: Map.merge(Map.new(allocated_workitems, &{&1.id, &1}), workitems)
      }

      {
        :reply,
        {:ok, allocated_workitems},
        state,
        {:continue, {:calibrate_workitems, :allocate, enabled_workitems}}
      }
    else
      {:error, exception} when is_exception(exception) ->
        {:reply, {:error, exception}, state}

      {:error, {:unsufficient_tokens, %Marking{} = marking}} ->
        exception =
          Exceptions.UnsufficientTokensToConsume.exception(
            enactment_id: state.enactment_id,
            place: marking.place,
            tokens: marking.tokens
          )

        {:reply, {:error, exception}, state}
    end
  end

  defp pop_workitems(%__MODULE__{} = state, workitem_ids, transition, expected_state) do
    case WorkitemConsumption.pop_workitems(state.workitems, workitem_ids, expected_state) do
      {:ok, _popped_workitems, _workitems} = ok ->
        ok

      {:error, {:workitem_not_found, workitem_id}} ->
        exception =
          Exceptions.NonLiveWorkitem.exception(
            id: workitem_id,
            enactment_id: state.enactment_id
          )

        {:error, exception}

      {:error, {:workitem_unexpected_state, workitem}} ->
        exception =
          Exceptions.InvalidWorkitemTransition.exception(
            id: workitem.id,
            enactment_id: state.enactment_id,
            state: workitem.state,
            transition: transition
          )

        {:error, exception}
    end
  end
end
