defmodule ColouredFlow.Runner.Enactment do
  @moduledoc """
  Each process instance represents one individual enactment of the process, using
  its own process instance data, and which is (normally) capable of independent
  control and audit as it progresses towards completion or termination.

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
  - `:exception` - An exception occurred during the enactment, and the
    corresponding enactment will be stopped.
  - `:terminated` - The enactment is terminated via `:implicit`, `:explicit`, or
    `:force`.
  """

  use GenServer, restart: :transient
  use TypedStructor

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.CatchingUp
  alias ColouredFlow.Runner.Enactment.EnactmentTermination
  alias ColouredFlow.Runner.Enactment.Lifespan
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

    field :timeout, timeout(),
      enforce: false,
      doc: "The enactment timeout; see `ColouredFlow.Runner.Enactment.Lifespan` for details."
  end

  @type option() ::
          {:enactment_id, enactment_id()}
          | {:timeout, timeout()}

  @type options() :: [option()]

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options) do
    enactment_id = Keyword.fetch!(options, :enactment_id)

    GenServer.start_link(
      __MODULE__,
      options,
      name: Registry.via_name({:enactment, enactment_id})
    )
  end

  @impl GenServer
  def init(options) do
    state = struct(__MODULE__, options)

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

    state = %__MODULE__{
      state
      | version: snapshot.version,
        markings: to_map(snapshot.markings),
        workitems: to_map(workitems)
    }

    emit_event(:start, state)

    {
      :noreply,
      state,
      {:continue, :calibrate_workitems}
    }
  end

  def handle_continue(:calibrate_workitems, %__MODULE__{} = state) do
    cpnet = Storage.get_flow_by_enactment(state.enactment_id)
    calibration = WorkitemCalibration.initial_calibrate(state, cpnet)
    state = apply_calibration(calibration)

    # try to terminate at the start
    case check_termination(state, cpnet) do
      {:stop, reason} -> {:stop, {:shutdown, reason}, state}
      :cont -> {:noreply, state, Lifespan.timeout(state)}
    end
  end

  def handle_continue(
        {:calibrate_workitems, transition, options},
        %__MODULE__{} = state
      )
      when is_list(options) do
    calibration = WorkitemCalibration.calibrate(state, transition, options)
    state = apply_calibration(calibration)

    if transition in [:complete, :complete_e] do
      cpnet = Storage.get_flow_by_enactment(state.enactment_id)
      # try to terminate when the transition is `:complete` or `:complete_e`
      case check_termination(state, cpnet) do
        {:stop, reason} -> {:stop, {:shutdown, reason}, state}
        :cont -> {:noreply, state, Lifespan.timeout(state)}
      end
    else
      {:noreply, state, Lifespan.timeout(state)}
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
        # the workitems from calibration.to_withdraw are not in `withdrawn` state
        grouped_wokitems =
          Enum.group_by(calibration.to_withdraw, & &1.state, &%Workitem{&1 | state: :withdrawn})

        workitems = Enum.flat_map(grouped_wokitems, &elem(&1, 1))

        Enum.each(grouped_wokitems, fn
          {:enabled, workitems} ->
            :ok = Storage.withdraw_workitems(workitems, action: :withdraw)

          {:started, workitems} ->
            :ok = Storage.withdraw_workitems(workitems, action: :withdraw_s)
        end)

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
  @spec check_termination(state(), ColouredPetriNet.t()) :: {:stop, reason :: binary()} | :cont
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

        emit_event(:terminate, state, %{termination_type: type})

        {:stop, "Terminated as #{type} criteria were met."}

      {:error, exception} ->
        :ok =
          Storage.exception_occurs(
            state.enactment_id,
            :termination_criteria_evaluation,
            exception
          )

        emit_event(:exception, state, %{
          exception_reason: :termination_criteria_evaluation,
          exception: exception
        })

        {:stop, "Terminated due to an exception in evaluating termination criteria."}
    end
  end

  @impl GenServer
  def handle_call({:terminate, options}, _from, %__MODULE__{} = state) when is_list(options) do
    :ok =
      Storage.terminate_enactment(
        state.enactment_id,
        :force,
        to_list(state.markings),
        options
      )

    message = Keyword.get(options, :message)
    emit_event(:terminate, state, %{termination_type: :force, termination_message: message})

    {:stop, {:shutdown, "Terminated manually"}, :ok, state}
  end

  def handle_call({:start_workitems, workitem_ids}, _from, %__MODULE__{} = state)
      when is_list(workitem_ids) do
    :start_workitems
    |> with_span(state, %{workitem_ids: workitem_ids}, fn ->
      with {:ok, {started_workitems, new_state}} <- start_workitems(state, workitem_ids) do
        :ok = Storage.start_workitems(started_workitems, action: :start)

        {:ok, {started_workitems, new_state}, %{workitems: started_workitems}}
      end
    end)
    |> case do
      {:ok, {started_workitems, new_state}} ->
        {
          :reply,
          {:ok, started_workitems},
          new_state,
          {:continue, {:calibrate_workitems, :start, [workitems: started_workitems]}}
        }

      {:error, exception} ->
        {:reply, {:error, exception}, state, Lifespan.timeout(state)}
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
        with(
          {:ok, transition_action, state} <- preflight_completion(state, workitem_ids),
          {:ok, {workitem_occurrences, new_state, calibration_options}} <-
            complete_workitems(state, workitem_ids, workitem_id_and_outputs)
        ) do
          :ok =
            Storage.complete_workitems(
              new_state.enactment_id,
              new_state.version,
              workitem_occurrences,
              action: transition_action
            )

          completed_workitems = Enum.map(workitem_occurrences, &elem(&1, 0))

          {
            :ok,
            {
              {completed_workitems, new_state},
              {:continue, {:calibrate_workitems, transition_action, calibration_options}}
            },
            %{workitems: completed_workitems}
          }
        end
      end
    )
    |> case do
      {:ok, {{completed_workitems, new_state}, continue}} ->
        :ok = GenServer.cast(self(), :take_snapshot)

        {:reply, {:ok, completed_workitems}, new_state, continue}

      {:error, exception} ->
        {:reply, {:error, exception}, state, Lifespan.timeout(state)}
    end
  end

  @impl GenServer
  def handle_cast(:take_snapshot, %__MODULE__{} = state) do
    Storage.take_enactment_snapshot(state.enactment_id, %Snapshot{
      version: state.version,
      markings: to_list(state.markings)
    })

    {:noreply, state, Lifespan.timeout(state)}
  end

  # we peek at the first workitem to pre-check the state
  @spec preflight_completion(state(), [Workitem.id()]) ::
          {:ok, :complete_e | :complete, state()} | {:error, Exception.t()}
  defp preflight_completion(%__MODULE__{} = state, workitem_ids)
       when is_list(workitem_ids) do
    state.workitems
    |> Enum.find_value(fn {workitem_id, %Workitem{} = workitem} ->
      if workitem_id in workitem_ids do
        {workitem.state, workitem_id}
      end
    end)
    |> case do
      nil ->
        exception =
          Exceptions.NonLiveWorkitem.exception(
            id: List.first(workitem_ids),
            enactment_id: state.enactment_id
          )

        {:error, exception}

      {:enabled, _workitem_id} ->
        with {:ok, {_started_workitems, new_state}} <- start_workitems(state, workitem_ids) do
          {:ok, :complete_e, new_state}
        end

      {:started, _workitem_id} ->
        {:ok, :complete, state}

      {workitem_state, workitem_id} ->
        exception =
          Exceptions.InvalidWorkitemTransition.exception(
            id: workitem_id,
            enactment_id: state.enactment_id,
            state: workitem_state,
            transition: :complete
          )

        {:error, exception}
    end
  end

  defp pop_workitems(%__MODULE__{} = state, workitem_ids, transition_action, expected_state) do
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
            transition: transition_action
          )

        {:error, exception}
    end
  end

  @spec start_workitems(state(), [Workitem.id()]) ::
          {
            :ok,
            {[Workitem.t(:started)], new_state :: state()}
          }
          | {:error, Exception.t()}
  defp start_workitems(%__MODULE__{} = state, workitem_ids) when is_list(workitem_ids) do
    with(
      {:ok, enabled_workitems, workitems} <-
        pop_workitems(state, workitem_ids, :start, :enabled),
      enabled_workitems = to_list(enabled_workitems),
      binding_elements = Enum.map(enabled_workitems, & &1.binding_element),
      # We don't need to remove the markings of the started workitems before `consume_tokens`,
      # because we withdraw workitems that are not enabled any more
      # after each `start_workitems` step by `calibrate_workitems`.
      {:ok, _markings} <- WorkitemConsumption.consume_tokens(state.markings, binding_elements)
    ) do
      started_workitems = Enum.map(enabled_workitems, &%Workitem{&1 | state: :started})

      new_state = %__MODULE__{
        state
        | workitems: merge_maps(started_workitems, workitems)
      }

      {:ok, {started_workitems, new_state}}
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

  @spec complete_workitems(
          state(),
          [Workitem.id()],
          Enumerable.t({Workitem.id(), Occurrence.free_binding()})
        ) ::
          {
            :ok,
            {
              workitem_occurrences :: [{Workitem.t(:completed), Occurrence.t()}],
              new_state :: state(),
              calibration_options :: Keyword.t()
            }
          }
          | {:error, Exception.t()}
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
      calibration_options = [cpnet: cpnet, workitem_occurrences: workitem_occurrences]

      {
        :ok,
        {
          workitem_occurrences,
          %__MODULE__{state | workitems: workitems},
          calibration_options
        }
      }
    else
      {:error, exception} when is_exception(exception) ->
        {:error, exception}
    end
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    {:stop, {:shutdown, "Terminated due to inactivity"}, state}
  end

  @impl GenServer
  def terminate({:shutdown, reason}, state) do
    emit_event(:stop, state, %{reason: reason})
  end

  def terminate(_reason, state) do
    emit_event(:stop, state, %{reason: "unknown"})
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

  defp emit_event(event, %__MODULE__{} = state, metadata \\ %{}) when is_map(metadata) do
    base_metadata = %{enactment_id: state.enactment_id, enactment_state: state}

    Telemetry.execute(
      [:coloured_flow, :runner, :enactment, event],
      %{},
      Enum.into(base_metadata, metadata)
    )
  end
end
