defmodule ColouredFlow.Runner.Enactment do
  @moduledoc """
  Each process instance represents one individual enactment of the process, using its
  own process instance data, and which is (normally) capable of independent control
  and audit as it progresses towards completion or termination.

  ## State

  ```mermaid
  ---
  title: The state machine of the enactment
  ---
  stateDiagram-v2
      direction LR

      [*] --> running

      running --> terminated
      running --> exception
      exception --> running
      exception --> terminated

      terminated --> [*]
  ```

  The enactment can be transitioned through several states:
  - `:running` - The enactment is running.
  - `:exception` - An exception occurred during the enactment, and the corresponding enactment will be stopped.
  - `:terminated` - The enactment is terminated via `:implicit`, `:explicit`, or `:force`.

  """

  use GenServer
  use TypedStructor

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment.CatchingUp
  alias ColouredFlow.Runner.Enactment.EnactmentTermination
  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Enactment.WorkitemCalibration
  alias ColouredFlow.Runner.Enactment.WorkitemCompletion
  alias ColouredFlow.Runner.Enactment.WorkitemConsumption
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Telemetry

  @typep enactment_id() :: Storage.enactment_id()

  @typedoc "The markings map of the enactment."
  @type markings() :: %{Place.name() => Marking.t()}
  @typedoc "The live workitems map of the enactment."
  @type workitems() :: %{Workitem.id() => Workitem.t(Workitem.live_state())}

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
          markings: to_map(snapshot.markings),
          workitems: to_map(workitems)
      },
      {:continue, :calibrate_workitems}
    }
  end

  def handle_continue(:calibrate_workitems, %__MODULE__{} = state) do
    cpnet = Storage.get_flow_by_enactment(state.enactment_id)
    calibration = WorkitemCalibration.initial_calibrate(state, cpnet)
    state = apply_calibration(calibration)

    # try to terminate at the start
    case check_termination(state, cpnet) do
      {:stop, _type} -> {:stop, :normal, state}
      :cont -> {:noreply, state}
    end
  end

  def handle_continue(
        {:calibrate_workitems, transition, options},
        %__MODULE__{} = state
      )
      when is_list(options) do
    calibration = WorkitemCalibration.calibrate(state, transition, options)
    state = apply_calibration(calibration)

    case transition do
      :complete ->
        cpnet = Storage.get_flow_by_enactment(state.enactment_id)
        # try to terminate when the transition is `:complete`
        case check_termination(state, cpnet) do
          {:stop, _type} -> {:stop, :normal, state}
          :cont -> {:noreply, state}
        end

      _other ->
        {:noreply, state}
    end
  end

  @spec catchup_snapshot(enactment_id(), Snapshot.t()) :: Snapshot.t()
  defp catchup_snapshot(enactment_id, snapshot) do
    occurrences = Storage.occurrences_stream(enactment_id, snapshot.version)

    {steps, markings} = CatchingUp.apply(snapshot.markings, occurrences)

    %Snapshot{snapshot | version: snapshot.version + steps, markings: markings}
  end

  defp apply_calibration(%WorkitemCalibration{state: %__MODULE__{} = state} = calibration) do
    # We don't need to ensure `withdraw_workitems` and `produce_workitems` are atomic,
    # because the gen_server will restart if the process crashes.
    with_span(
      :withdraw_workitems,
      state,
      %{workitem_ids: Enum.map(calibration.to_withdraw, & &1.id)},
      fn ->
        workitems = Storage.withdraw_workitems(calibration.to_withdraw)
        {:ok, workitems, %{workitems: workitems}}
      end
    )

    {:ok, produced_workitems} =
      with_span(
        :produce_workitems,
        state,
        %{binding_elements: calibration.to_produce},
        fn ->
          workitems = Storage.produce_workitems(state.enactment_id, calibration.to_produce)
          {:ok, to_map(workitems), %{workitems: workitems}}
        end
      )

    %__MODULE__{state | workitems: Map.merge(state.workitems, produced_workitems)}
  end

  # `:explicit` takes priority over `:implicit`
  @spec check_termination(state(), ColouredPetriNet.t()) ::
          {:stop, :explicit | :implicit | :exception} | :cont
  defp check_termination(%__MODULE__{} = state, cpnet) do
    import EnactmentTermination

    markings = to_list(state.markings)

    with(
      :cont <- check_explicit_termination(cpnet.termination_criteria, markings),
      :cont <- check_implicit_termination(to_list(state.workitems))
    ) do
      :cont
    else
      {:stop, type} when type in [:explicit, :implicit] ->
        :ok = Storage.terminate_enactment(state.enactment_id, type, markings, [])

        {:stop, type}

      {:error, exception} ->
        :ok =
          Storage.exception_occurs(
            state.enactment_id,
            :termination_criteria_evaluation,
            exception
          )

        {:stop, :exception}
    end
  end

  @impl GenServer
  def handle_call({:allocate_workitems, workitem_ids}, _from, %__MODULE__{} = state)
      when is_list(workitem_ids) do
    :allocate_workitems
    |> with_span(state, %{workitem_ids: workitem_ids}, fn ->
      allocate_workitems(state, workitem_ids)
    end)
    |> case do
      {:ok, {reply, new_state, continue}} ->
        {:reply, reply, new_state, continue}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  def handle_call({:start_workitems, workitem_ids}, _from, %__MODULE__{} = state)
      when is_list(workitem_ids) do
    :start_workitems
    |> with_span(state, %{workitem_ids: workitem_ids}, fn ->
      start_workitems(state, workitem_ids)
    end)
    |> case do
      {:ok, {reply, new_state}} ->
        {:reply, reply, new_state}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  def handle_call(
        {:complete_workitems, workitem_id_and_outputs},
        _from,
        %__MODULE__{} = state
      ) do
    workitem_ids = Enum.map(workitem_id_and_outputs, &elem(&1, 0))

    :complete_workitems
    |> with_span(
      state,
      %{workitem_ids: workitem_ids, workitem_id_and_outputs: workitem_id_and_outputs},
      fn ->
        complete_workitems(state, workitem_ids, workitem_id_and_outputs)
      end
    )
    |> case do
      {:ok, {reply, new_state, continue}} ->
        :ok = GenServer.cast(self(), :take_snapshot)

        {:reply, reply, new_state, continue}

      {:error, exception} ->
        {:reply, {:error, exception}, state}
    end
  end

  @impl GenServer
  def handle_cast(:take_snapshot, %__MODULE__{} = state) do
    Storage.take_enactment_snapshot(state.enactment_id, %Snapshot{
      version: state.version,
      markings: to_list(state.markings)
    })

    {:noreply, state}
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

  defp allocate_workitems(%__MODULE__{} = state, workitem_ids) when is_list(workitem_ids) do
    with(
      {:ok, enabled_workitems, workitems} <-
        pop_workitems(state, workitem_ids, :allocate, :enabled),
      enabled_workitems = to_list(enabled_workitems),
      binding_elements = Enum.map(enabled_workitems, & &1.binding_element),
      # We don't need to remove the markings of the allocated workitems before `consume_tokens`,
      # because we withdraw workitems that are not enabled any more
      # after each `allocated_workitems` step by `calibrate_workitems`.
      {:ok, _markings} <- WorkitemConsumption.consume_tokens(state.markings, binding_elements)
    ) do
      allocated_workitems = Storage.allocate_workitems(enabled_workitems)

      state = %__MODULE__{
        state
        | workitems: merge_maps(allocated_workitems, workitems)
      }

      {
        :ok,
        {
          {:ok, allocated_workitems},
          state,
          {:continue, {:calibrate_workitems, :allocate, [workitems: enabled_workitems]}}
        },
        %{workitems: allocated_workitems}
      }
    else
      {:error, exception} when is_exception(exception) ->
        {:error, exception}

      {:error, {:unsufficient_tokens, %Marking{} = marking}} ->
        exception =
          Exceptions.UnsufficientTokensToConsume.exception(
            enactment_id: state.enactment_id,
            place: marking.place,
            tokens: marking.tokens
          )

        {:error, exception}
    end
  end

  defp start_workitems(%__MODULE__{} = state, workitem_ids) when is_list(workitem_ids) do
    case pop_workitems(state, workitem_ids, :start, :allocated) do
      {:ok, allocated_workitems, workitems} ->
        allocated_workitems = to_list(allocated_workitems)
        started_workitems = Storage.start_workitems(allocated_workitems)

        state = %__MODULE__{
          state
          | workitems: merge_maps(started_workitems, workitems)
        }

        {:ok, {{:ok, started_workitems}, state}, %{workitems: started_workitems}}

      {:error, exception} when is_exception(exception) ->
        {:error, exception}
    end
  end

  defp complete_workitems(%__MODULE__{} = state, workitem_ids, workitem_id_and_outputs)
       when is_list(workitem_ids) do
    with(
      {:ok, started_workitems, workitems} <-
        pop_workitems(state, workitem_ids, :complete, :started),
      workitem_and_outputs =
        Enum.map(workitem_id_and_outputs, fn {workitem_id, free_binding} ->
          {Map.fetch!(started_workitems, workitem_id), free_binding}
        end),
      cpnet = Storage.get_flow_by_enactment(state.enactment_id),
      {:ok, workitem_occurrences} <- WorkitemCompletion.complete(workitem_and_outputs, cpnet)
    ) do
      #  wrapped in a transaction
      completed_workitems =
        Storage.complete_workitems(state.enactment_id, state.version, workitem_occurrences)

      {
        :ok,
        {
          {:ok, completed_workitems},
          %__MODULE__{state | workitems: workitems},
          {
            :continue,
            {
              :calibrate_workitems,
              :complete,
              [cpnet: cpnet, workitem_occurrences: workitem_occurrences]
            }
          }
        },
        %{workitems: completed_workitems}
      }
    else
      {:error, exception} when is_exception(exception) ->
        {:error, exception}
    end
  end

  @spec to_map(Enumerable.t(item)) :: %{Place.name() => item} when item: Marking.t()
  @spec to_map(Enumerable.t(item)) :: %{Workitem.id() => item} when item: Workitem.t()
  def to_map([]), do: %{}
  def to_map([%Workitem{} = workitem | rest]), do: Map.put(to_map(rest), workitem.id, workitem)
  def to_map([%Marking{} = marking | rest]), do: Map.put(to_map(rest), marking.place, marking)

  @spec to_list(%{Place.name() => item}) :: [item] when item: Marking.t()
  @spec to_list(%{Workitem.id() => item}) :: [item] when item: Workitem.t()
  def to_list(map) when is_map(map), do: Map.values(map)

  @spec merge_maps(Enumerable.t(item) | amap, amap) :: amap
        when item: Marking.t(), amap: %{Place.name() => item}
  @spec merge_maps(Enumerable.t(item) | amap, amap) :: amap
        when item: Workitem.t(), amap: %{Workitem.id() => item}
  defp merge_maps(map1, map2) when is_map(map1) and is_map(map2), do: Map.merge(map1, map2)
  defp merge_maps(list, map) when is_list(list) and is_map(map), do: merge_maps(to_map(list), map)

  @spec with_span(
          event :: atom(),
          state(),
          base_metadata :: Telemetry.event_metadata(),
          span_function :: Telemetry.span_function(result, exception)
        ) :: {:ok, result} | {:error, exception}
        when result: var, exception: Exception.t()
  defp with_span(event, %__MODULE__{} = state, base_metadata, span_function)
       when is_atom(event) and is_function(span_function, 0) do
    start_metadata =
      Map.merge(base_metadata, %{enactment_id: state.enactment_id, enactment_state: state})

    Telemetry.span([:coloured_flow, :runner, :enactment, event], start_metadata, fn ->
      case span_function.() do
        {:ok, result, stop_metadata} ->
          {:ok, result, Map.merge(start_metadata, stop_metadata)}

        # the extra_measurements are not used in this case, comment out for dialyzer
        # {:ok, result, extra_measurements, stop_metadata} ->
        #   {:ok, result, extra_measurements, Map.merge(start_metadata, stop_metadata)}

        {:error, exception} ->
          {:error, exception}
      end
    end)
  end
end
