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
  alias ColouredFlow.Runner.Errors
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.RuntimeCpnet
  alias ColouredFlow.Runner.Storage
  alias ColouredFlow.Runner.Telemetry

  require Logger

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

    field :hibernate_after, timeout(),
      enforce: false,
      doc:
        "The idle duration after which the GenServer hibernates; " <>
          "see `ColouredFlow.Runner.Enactment.Lifespan` for details."
  end

  @type option() ::
          {:enactment_id, enactment_id()}
          | {:timeout, timeout()}
          | {:hibernate_after, timeout()}

  @type options() :: [option()]

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options) do
    enactment_id = Keyword.fetch!(options, :enactment_id)
    # Forward `$callers` from the calling process so collaborating processes
    # (e.g., Ecto.Adapters.SQL.Sandbox-aware tests) can be tracked. See
    # `ExUnit.Callbacks.start_supervised/2` for the recommended pattern.
    options = Keyword.put_new(options, :"$callers", Process.get(:"$callers", []))

    GenServer.start_link(
      __MODULE__,
      options,
      name: Registry.via_name({:enactment, enactment_id}),
      hibernate_after: Lifespan.hibernate_after_from_options(options)
    )
  end

  @impl GenServer
  def init(options) do
    {callers, options} = Keyword.pop(options, :"$callers", [])
    Process.put(:"$callers", callers)

    options =
      Keyword.put(options, :hibernate_after, Lifespan.hibernate_after_from_options(options))

    state = struct(__MODULE__, options)

    {:ok, state, {:continue, :populate_state}}
  end

  @impl GenServer
  def handle_continue(:populate_state, %__MODULE__{} = state) do
    with(
      {:ok, snapshot, had_snapshot?} <- load_initial_snapshot(state),
      {:ok, snapshot, replayed_steps} <- replay_occurrences(state, snapshot)
    ) do
      maybe_persist_bootstrap_snapshot(state, snapshot)

      workitems = Storage.list_live_workitems(state.enactment_id)

      state = %__MODULE__{
        state
        | version: snapshot.version,
          markings: to_map(snapshot.markings),
          workitems: to_map(workitems)
      }

      # Always emit `:start` for backward compatibility; the new `resumed`
      # metadata flag distinguishes a fresh boot from a crash recovery
      # (snapshot loaded, or occurrences replayed).
      resumed? = had_snapshot? or replayed_steps > 0
      emit_event(:start, state, %{resumed: resumed?, replayed_steps: replayed_steps})

      {:noreply, state, {:continue, :calibrate_workitems}}
    else
      {:fatal, reason, ctx} -> to_exception(state, reason, ctx)
    end
  end

  def handle_continue(:calibrate_workitems, %__MODULE__{} = state) do
    runtime_cpnet = build_runtime_cpnet(state.enactment_id)
    calibration = WorkitemCalibration.initial_calibrate(state, runtime_cpnet)

    case apply_calibration(calibration) do
      {:ok, state} ->
        # try to terminate at the start
        case check_termination(state, runtime_cpnet.definition) do
          :cont -> {:noreply, state, Lifespan.timeout(state)}
          {:stop, _reason, _state} = stop -> stop
        end

      {:error, %Exceptions.StateDrift{} = ex} ->
        to_exception(state, :state_drift, %{
          phase: :calibrate_workitems,
          operation: ex.operation,
          context: ex.context
        })
    end
  rescue
    e in [Ecto.NoResultsError] ->
      to_exception(state, :enactment_data_missing, %{
        phase: :calibrate_workitems,
        missing: :flow,
        underlying: e
      })

    e in [
      ColouredFlow.Definition.ColourSet.ColourSetMismatch,
      ArgumentError,
      KeyError,
      MatchError,
      RuntimeError
    ] ->
      # `RuntimeCpnet.from_definition/1` and the `Utils.fetch_*!` lookup
      # helpers raise plain `RuntimeError` when the persisted CPN refers
      # to a missing place / colour set / variable / transition. Catch
      # those (and codec value-shape errors) so a corrupt stored
      # definition routes to the Tier 2 funnel instead of escalating to
      # a Tier 3 supervisor restart.
      to_exception(state, :cpnet_corrupt, %{
        phase: :calibrate_workitems,
        underlying: e
      })
  end

  def handle_continue(
        {:calibrate_workitems, transition, options},
        %__MODULE__{} = state
      )
      when is_list(options) do
    calibration = WorkitemCalibration.calibrate(state, transition, options)

    case apply_calibration(calibration) do
      {:ok, state} ->
        maybe_check_termination_after(state, transition, options)

      {:error, %Exceptions.StateDrift{} = ex} ->
        to_exception(state, :state_drift, %{
          phase: :calibrate_workitems,
          operation: ex.operation,
          context: ex.context
        })
    end
  rescue
    e in [Ecto.NoResultsError] ->
      to_exception(state, :enactment_data_missing, %{
        phase: :calibrate_workitems,
        missing: :flow,
        underlying: e
      })

    e in [
      ColouredFlow.Definition.ColourSet.ColourSetMismatch,
      ArgumentError,
      KeyError,
      MatchError,
      RuntimeError
    ] ->
      # `RuntimeCpnet.from_definition/1` and the `Utils.fetch_*!` lookup
      # helpers raise plain `RuntimeError` when the persisted CPN refers
      # to a missing place / colour set / variable / transition. Catch
      # those here so a corrupt stored definition routes to the Tier 2
      # funnel instead of escalating to a Tier 3 supervisor restart.
      to_exception(state, :cpnet_corrupt, %{
        phase: :calibrate_workitems,
        underlying: e
      })
  end

  defp maybe_check_termination_after(%__MODULE__{} = state, transition, options) do
    if transition in [:complete, :complete_e] do
      # try to terminate when the transition is `:complete` or `:complete_e`.
      # `complete_workitems/3` always threads the runtime cpnet through the
      # calibration options, so we reuse it here instead of re-fetching.
      %RuntimeCpnet{definition: cpnet} = Keyword.fetch!(options, :runtime_cpnet)

      case check_termination(state, cpnet) do
        :cont -> {:noreply, state, Lifespan.timeout(state)}
        {:stop, _reason, _state} = stop -> stop
      end
    else
      {:noreply, state, Lifespan.timeout(state)}
    end
  end

  # Load the snapshot row (or build the initial-markings snapshot when the
  # enactment has never reached its first persisted snapshot).
  #
  # Errors raised here are attributed to snapshot decoding or to a missing
  # `enactments` row, never to occurrence replay.
  defp load_initial_snapshot(%__MODULE__{} = state) do
    case Storage.read_enactment_snapshot(state.enactment_id) do
      {:ok, snapshot} ->
        {:ok, snapshot, true}

      :error ->
        {:ok,
         %Snapshot{
           version: 0,
           markings: Storage.get_initial_markings(state.enactment_id)
         }, false}
    end
  rescue
    e in [Ecto.NoResultsError] ->
      {:fatal, :enactment_data_missing,
       %{phase: :populate_state, missing: :enactment, underlying: e}}

    e in [
      ColouredFlow.Definition.ColourSet.ColourSetMismatch,
      ArgumentError,
      KeyError,
      MatchError
    ] ->
      {:fatal, :snapshot_corrupt, %{phase: :populate_state, underlying: e}}
  end

  # Apply the persisted occurrence stream from the loaded snapshot's version
  # forward.
  #
  # Errors raised here are attributed to occurrence replay (codec corruption
  # on the occurrence row, MultiSet mismatch, etc.), not to snapshot decoding.
  defp replay_occurrences(%__MODULE__{} = state, %Snapshot{} = snapshot) do
    {snapshot, replayed_steps} = catchup_snapshot(state.enactment_id, snapshot)
    {:ok, snapshot, replayed_steps}
  rescue
    e in [
      ArgumentError,
      KeyError,
      MatchError,
      ColouredFlow.Definition.ColourSet.ColourSetMismatch
    ] ->
      {:fatal, :replay_failed, %{phase: :populate_state, underlying: e}}
  end

  defp maybe_persist_bootstrap_snapshot(%__MODULE__{} = state, %Snapshot{} = snapshot) do
    case Storage.take_enactment_snapshot(state.enactment_id, snapshot) do
      :ok ->
        :ok

      {:error, {:snapshot_persistence_failed, ctx}} ->
        # Bootstrap snapshot write is best-effort. Worst case the next
        # restart replays from an older snapshot; data is not lost.
        Logger.warning(
          "Bootstrap snapshot persistence failed for enactment " <>
            "#{inspect(state.enactment_id)} at version #{snapshot.version}: " <>
            "#{inspect(ctx)}"
        )
    end
  end

  @spec catchup_snapshot(enactment_id(), Snapshot.t()) ::
          {Snapshot.t(), replayed_steps :: non_neg_integer()}
  defp catchup_snapshot(enactment_id, %Snapshot{} = snapshot) do
    occurrences = Storage.occurrences_stream(enactment_id, snapshot.version)

    {steps, markings} = CatchingUp.apply(snapshot.markings, occurrences)

    {%{snapshot | version: snapshot.version + steps, markings: markings}, steps}
  end

  @spec apply_calibration(WorkitemCalibration.t()) ::
          {:ok, state()} | {:error, Exception.t()}
  defp apply_calibration(%WorkitemCalibration{state: %__MODULE__{} = state} = calibration) do
    with(
      {:ok, _withdrawn} <- run_withdraw_step(state, calibration.to_withdraw),
      {:ok, produced_workitems_map} <- run_produce_step(state, calibration.to_produce)
    ) do
      {:ok, %__MODULE__{state | workitems: Map.merge(state.workitems, produced_workitems_map)}}
    end
  end

  defp run_withdraw_step(%__MODULE__{} = state, to_withdraw) do
    with_span(
      :withdraw_workitems,
      state,
      %{workitem_ids: Enum.map(to_withdraw, & &1.id)},
      fn ->
        # the workitems from `to_withdraw` are not yet in `withdrawn` state
        grouped_workitems =
          Enum.group_by(to_withdraw, & &1.state, fn %Workitem{} = workitem ->
            %{workitem | state: :withdrawn}
          end)

        workitems = Enum.flat_map(grouped_workitems, &elem(&1, 1))

        case withdraw_grouped_workitems(grouped_workitems) do
          :ok ->
            {:ok, workitems, %{workitems: workitems}}

          {:error, {:state_drift, ctx}} ->
            {:error,
             Exceptions.StateDrift.exception(
               enactment_id: state.enactment_id,
               operation: :withdraw_workitems,
               context: ctx
             )}
        end
      end
    )
  end

  defp withdraw_grouped_workitems(grouped) do
    Enum.reduce_while(grouped, :ok, fn {workitem_state, workitems}, _acc ->
      action =
        case workitem_state do
          :enabled -> :withdraw
          :started -> :withdraw_s
        end

      case Storage.withdraw_workitems(workitems, action: action) do
        :ok -> {:cont, :ok}
        {:error, _drift} = error -> {:halt, error}
      end
    end)
  end

  defp run_produce_step(%__MODULE__{} = state, to_produce) do
    with_span(
      :produce_workitems,
      state,
      %{binding_elements: to_produce},
      fn ->
        case Storage.produce_workitems(state.enactment_id, to_produce) do
          {:error, {:produce_persistence_failed, ctx}} ->
            {:error,
             Exceptions.StateDrift.exception(
               enactment_id: state.enactment_id,
               operation: :produce_workitems,
               context: ctx
             )}

          workitems when is_list(workitems) ->
            {:ok, to_map(workitems), %{workitems: workitems}}
        end
      end
    )
  end

  # `:explicit` takes priority over `:implicit`
  # credo:disable-for-lines:2 JetCredo.Checks.ExplicitAnyType
  @spec check_termination(state(), ColouredPetriNet.t()) ::
          :cont | {:stop, term(), state()}
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
        perform_termination(state, type, markings, [])

      {:error, exception} ->
        to_exception(state, :termination_criteria_evaluation, %{
          phase: :check_termination,
          exception: exception
        })
    end
  end

  # credo:disable-for-lines:6 JetCredo.Checks.ExplicitAnyType
  @spec perform_termination(
          state(),
          ColouredFlow.Runner.Termination.type(),
          [Marking.t()],
          options :: [message: String.t()]
        ) :: {:stop, term(), state()}
  defp perform_termination(%__MODULE__{} = state, type, markings, options) do
    case Storage.terminate_enactment(state.enactment_id, type, markings, options) do
      :ok ->
        emit_event(:terminate, state, %{
          termination_type: type,
          termination_message: Keyword.get(options, :message)
        })

        {:stop, {:shutdown, {:terminated, type}}, state}

      {:error, {:terminate_persistence_failed, ctx}} ->
        to_exception(state, :state_drift, %{
          phase: :perform_termination,
          operation: :terminate_enactment,
          context: Map.put(ctx, :termination_type, type)
        })
    end
  end

  # The unified Tier 2 fatal-stop funnel.
  #
  # Persists the enactment as `:exception`, emits a lifecycle exception event,
  # and stops the GenServer with `{:shutdown, {:fatal, reason}}` so the
  # supervisor does not count it against `max_restarts`. If the persistence
  # itself fails (leak mode 1, see `error_handling_design.md` §7) the funnel
  # falls through to an abnormal exit so the supervisor can retry.
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec to_exception(state(), atom(), map()) :: {:stop, term(), state()}
  defp to_exception(%__MODULE__{} = state, reason, ctx) do
    full_ctx = Map.put(ctx, :enactment_id, state.enactment_id)
    exception = Errors.build_exception(reason, full_ctx)

    case Storage.exception_occurs(state.enactment_id, reason, exception) do
      :ok ->
        emit_event(:exception, state, %{
          tier: 2,
          lifecycle: true,
          severity: :fatal,
          source_phase: ctx[:phase],
          exception_reason: reason,
          error_code: Errors.error_code(exception),
          exception: exception,
          degraded: false
        })

        {:stop, {:shutdown, {:fatal, reason}}, state}

      {:error, persistence_error} ->
        emit_event(:exception, state, %{
          tier: 2,
          lifecycle: true,
          severity: :fatal,
          source_phase: ctx[:phase],
          exception_reason: reason,
          error_code: Errors.error_code(exception),
          exception: exception,
          degraded: true,
          persistence_error: persistence_error
        })

        Logger.error(
          "Tier 2 fatal but persistence failed for enactment " <>
            "#{inspect(state.enactment_id)}: reason=#{reason}, " <>
            "persistence_error=#{inspect(persistence_error)}"
        )

        {:stop, {:fatal_persistence_failed, persistence_error}, state}
    end
  end

  @impl GenServer
  def handle_call({:terminate, options}, _from, %__MODULE__{} = state) when is_list(options) do
    markings = to_list(state.markings)

    case Storage.terminate_enactment(state.enactment_id, :force, markings, options) do
      :ok ->
        emit_event(:terminate, state, %{
          termination_type: :force,
          termination_message: Keyword.get(options, :message)
        })

        {:stop, {:shutdown, {:terminated, :force}}, :ok, state}

      {:error, {:terminate_persistence_failed, ctx}} ->
        ctx = Map.put(ctx, :termination_type, :force)

        {:stop, stop_reason, state} =
          to_exception(state, :state_drift, %{
            phase: :handle_terminate,
            operation: :terminate_enactment,
            context: ctx
          })

        drift_ex =
          Exceptions.StateDrift.exception(
            enactment_id: state.enactment_id,
            operation: :terminate_enactment,
            context: ctx
          )

        {:stop, stop_reason, {:error, drift_ex}, state}
    end
  end

  def handle_call({:start_workitems, workitem_ids}, _from, %__MODULE__{} = state)
      when is_list(workitem_ids) do
    :start_workitems
    |> with_span(state, %{workitem_ids: workitem_ids}, fn ->
      do_start_workitems(state, workitem_ids)
    end)
    |> case do
      {:ok, {started_workitems, new_state}} ->
        {
          :reply,
          {:ok, started_workitems},
          new_state,
          {:continue, {:calibrate_workitems, :start, [workitems: started_workitems]}}
        }

      {:error, %Exceptions.StateDrift{} = ex} ->
        {:stop, stop_reason, new_state} =
          to_exception(state, :state_drift, %{
            phase: :handle_start_workitems,
            operation: ex.operation,
            context: ex.context
          })

        {:stop, stop_reason, {:error, ex}, new_state}

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
            complete_workitems(state, workitem_ids, workitem_id_and_outputs),
          :ok <-
            Storage.complete_workitems(
              new_state.enactment_id,
              new_state.version,
              workitem_occurrences,
              action: transition_action
            )
        ) do
          completed_workitems = Enum.map(workitem_occurrences, &elem(&1, 0))

          {
            :ok,
            {
              {completed_workitems, new_state},
              {:continue, {:calibrate_workitems, transition_action, calibration_options}}
            },
            %{workitems: completed_workitems}
          }
        else
          {:error, ex} when is_exception(ex) ->
            {:error, ex}

          {:error, {:state_drift, ctx}} ->
            {:error,
             Exceptions.StateDrift.exception(
               enactment_id: state.enactment_id,
               operation: :complete_workitems,
               context: ctx
             )}
        end
      end
    )
    |> case do
      {:ok, {{completed_workitems, new_state}, continue}} ->
        send(self(), :take_snapshot)

        {:reply, {:ok, completed_workitems}, new_state, continue}

      {:error, %Exceptions.StateDrift{} = ex} ->
        {:stop, stop_reason, new_state} =
          to_exception(state, :state_drift, %{
            phase: :handle_complete_workitems,
            operation: ex.operation,
            context: ex.context
          })

        {:stop, stop_reason, {:error, ex}, new_state}

      {:error, exception} ->
        {:reply, {:error, exception}, state, Lifespan.timeout(state)}
    end
  rescue
    e in [Ecto.NoResultsError] ->
      # `Storage.get_flow_by_enactment/1` raised because the flow row is gone.
      ex =
        Exceptions.EnactmentDataMissing.exception(
          enactment_id: state.enactment_id,
          missing: :flow
        )

      {:stop, stop_reason, new_state} =
        to_exception(state, :enactment_data_missing, %{
          phase: :handle_complete_workitems,
          missing: :flow,
          underlying: e
        })

      {:stop, stop_reason, {:error, ex}, new_state}

    e in [
      ColouredFlow.Definition.ColourSet.ColourSetMismatch,
      ArgumentError,
      KeyError,
      MatchError,
      RuntimeError
    ] ->
      ex =
        Exceptions.CpnetCorrupt.exception(
          enactment_id: state.enactment_id,
          underlying: e
        )

      {:stop, stop_reason, new_state} =
        to_exception(state, :cpnet_corrupt, %{
          phase: :handle_complete_workitems,
          underlying: e
        })

      {:stop, stop_reason, {:error, ex}, new_state}
  end

  defp do_start_workitems(%__MODULE__{} = state, workitem_ids) do
    with(
      {:ok, {started_workitems, new_state}} <- start_workitems(state, workitem_ids),
      :ok <- Storage.start_workitems(started_workitems, action: :start)
    ) do
      {:ok, {started_workitems, new_state}, %{workitems: started_workitems}}
    else
      {:error, {:state_drift, ctx}} ->
        {:error,
         Exceptions.StateDrift.exception(
           enactment_id: state.enactment_id,
           operation: :start_workitems,
           context: ctx
         )}

      {:error, ex} when is_exception(ex) ->
        {:error, ex}
    end
  end

  # we peek at the first workitem to pre-check the state
  @spec preflight_completion(state(), [Workitem.id()]) ::
          {:ok, :complete_e | :complete, state()} | {:error, Exception.t()}
  defp preflight_completion(%__MODULE__{} = state, workitem_ids)
       when is_list(workitem_ids) do
    workitem_id_set = MapSet.new(workitem_ids)

    state.workitems
    |> Enum.find_value(fn {workitem_id, %Workitem{} = workitem} ->
      if MapSet.member?(workitem_id_set, workitem_id) do
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
      started_workitems =
        Enum.map(enabled_workitems, fn %Workitem{} = workitem ->
          %{workitem | state: :started}
        end)

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
      runtime_cpnet = build_runtime_cpnet(state.enactment_id),
      {:ok, workitem_occurrences} <-
        WorkitemCompletion.complete(workitem_and_outputs, runtime_cpnet)
    ) do
      calibration_options = [
        runtime_cpnet: runtime_cpnet,
        workitem_occurrences: workitem_occurrences
      ]

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

  @spec build_runtime_cpnet(enactment_id()) :: RuntimeCpnet.t()
  defp build_runtime_cpnet(enactment_id) do
    enactment_id
    |> Storage.get_flow_by_enactment()
    |> RuntimeCpnet.from_definition()
  end

  @impl GenServer
  def handle_info(:take_snapshot, %__MODULE__{} = state) do
    drain_take_snapshot_messages()

    emit_event(:take_snapshot, state)

    snapshot = %Snapshot{version: state.version, markings: to_list(state.markings)}

    case Storage.take_enactment_snapshot(state.enactment_id, snapshot) do
      :ok ->
        :ok

      {:error, {:snapshot_persistence_failed, ctx}} ->
        # Snapshot writes are best-effort; an asynchronous failure is not
        # fatal. Log and continue. The next `complete_workitems` will send
        # another snapshot attempt.
        Logger.warning(
          "Async snapshot persistence failed for enactment " <>
            "#{inspect(state.enactment_id)} at version #{state.version}: " <>
            "#{inspect(ctx)}"
        )
    end

    {:noreply, state, Lifespan.timeout(state)}
  end

  def handle_info(:timeout, state) do
    {:stop, {:shutdown, "Terminated due to inactivity"}, state}
  end

  # Selectively drain any queued `:take_snapshot` messages in the mailbox so
  # bursts of `complete_workitems` collapse into a single storage write of the
  # latest state.
  @spec drain_take_snapshot_messages() :: :ok
  defp drain_take_snapshot_messages do
    receive do
      :take_snapshot -> drain_take_snapshot_messages()
    after
      0 -> :ok
    end
  end

  @impl GenServer
  def terminate({:shutdown, {:fatal, fatal_reason}}, state) when is_atom(fatal_reason) do
    emit_event(:stop, state, %{
      reason: "Terminated due to a fatal error: #{fatal_reason}.",
      fatal_reason: fatal_reason
    })
  end

  def terminate({:shutdown, {:terminated, :force}}, state) do
    emit_event(:stop, state, %{
      reason: "Terminated manually",
      termination_type: :force
    })
  end

  def terminate({:shutdown, {:terminated, termination_type}}, state)
      when is_atom(termination_type) do
    emit_event(:stop, state, %{
      reason: "Terminated as #{termination_type} criteria were met.",
      termination_type: termination_type
    })
  end

  def terminate({:shutdown, reason}, state) when is_binary(reason) do
    emit_event(:stop, state, %{reason: reason})
  end

  def terminate({:shutdown, reason}, state) do
    emit_event(:stop, state, %{reason: inspect(reason)})
  end

  def terminate({:fatal_persistence_failed, persistence_error}, state) do
    emit_event(:stop, state, %{
      reason: "Terminated because the fatal-state persistence layer itself failed.",
      persistence_error: inspect(persistence_error)
    })
  end

  def terminate(reason, state) do
    emit_event(:stop, state, %{reason: inspect(reason)})
  end

  @spec to_map(Enumerable.t(item)) :: %{Place.name() => item} when item: Marking.t()
  @spec to_map(Enumerable.t(item)) :: %{Workitem.id() => item} when item: Workitem.t()
  def to_map(items) do
    Map.new(items, fn
      %Workitem{} = workitem -> {workitem.id, workitem}
      %Marking{} = marking -> {marking.place, marking}
    end)
  end

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
