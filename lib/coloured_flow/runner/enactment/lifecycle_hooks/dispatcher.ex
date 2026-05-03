defmodule ColouredFlow.Runner.Enactment.LifecycleHooks.Dispatcher do
  @moduledoc """
  Maps the runner's internal enactment events to the per-instance
  `ColouredFlow.Runner.Enactment.LifecycleHooks` callbacks. Internal helper for
  `ColouredFlow.Runner.Enactment` — couples intentionally to the runner state
  struct so callsites stay one-line delegations.
  """

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Enactment.LifecycleHooks

  @typep state() :: Enactment.state()

  # Run after `apply_calibration/1` so handlers see the post-firing markings.
  # `:start` and `:complete*` dispatches happen here because they are the
  # transitions that mutate `state.markings`.
  @spec dispatch_post_calibration(atom(), state(), keyword()) :: :ok
  def dispatch_post_calibration(:start, %Enactment{} = state, options) do
    workitems = Keyword.get(options, :workitems, [])
    dispatch(:start_workitems, state, %{workitems: workitems})
  end

  def dispatch_post_calibration(transition, %Enactment{} = state, options)
      when transition in [:complete, :complete_e] do
    workitem_occurrences = Keyword.get(options, :workitem_occurrences, [])
    dispatch(:complete_workitems, state, %{workitem_occurrences: workitem_occurrences})
  end

  def dispatch_post_calibration(_other, _state, _options), do: :ok

  # Map the runner's internal events to the per-enactment LifecycleHooks
  # callbacks. Telemetry keeps emitting in addition.
  @spec dispatch(atom(), state(), map()) :: :ok
  def dispatch(_event, %Enactment{lifecycle_hooks: nil}, _metadata), do: :ok

  def dispatch(:start, %Enactment{lifecycle_hooks: hooks} = state, _meta) do
    event = %{enactment_id: state.enactment_id, markings: markings_snapshot(state)}
    LifecycleHooks.safe_invoke(hooks, :on_enactment_start, [event])
  end

  def dispatch(:terminate, %Enactment{lifecycle_hooks: hooks} = state, %{
        termination_type: type
      }) do
    event = %{
      enactment_id: state.enactment_id,
      markings: markings_snapshot(state),
      reason: type
    }

    LifecycleHooks.safe_invoke(hooks, :on_enactment_terminate, [event])
  end

  def dispatch(:exception, %Enactment{lifecycle_hooks: hooks} = state, %{
        exception_reason: reason
      }) do
    event = %{
      enactment_id: state.enactment_id,
      markings: markings_snapshot(state),
      reason: reason
    }

    LifecycleHooks.safe_invoke(hooks, :on_enactment_exception, [event])
  end

  def dispatch(:produce_workitems, %Enactment{lifecycle_hooks: hooks} = state, %{
        workitems: workitems
      })
      when is_list(workitems) do
    markings = markings_snapshot(state)

    Enum.each(workitems, fn workitem ->
      event = %{
        enactment_id: state.enactment_id,
        markings: markings,
        workitem: workitem,
        binding: workitem.binding_element.binding
      }

      LifecycleHooks.safe_invoke(hooks, :on_workitem_enabled, [event])
    end)
  end

  def dispatch(:start_workitems, %Enactment{lifecycle_hooks: hooks} = state, %{
        workitems: workitems
      })
      when is_list(workitems) do
    markings = markings_snapshot(state)

    Enum.each(workitems, fn workitem ->
      event = %{
        enactment_id: state.enactment_id,
        markings: markings,
        workitem: workitem,
        binding: workitem.binding_element.binding
      }

      LifecycleHooks.safe_invoke(hooks, :on_workitem_started, [event])
    end)
  end

  def dispatch(:complete_workitems, %Enactment{lifecycle_hooks: hooks} = state, %{
        workitem_occurrences: workitem_occurrences
      })
      when is_list(workitem_occurrences) do
    markings = markings_snapshot(state)

    Enum.each(workitem_occurrences, fn {workitem, occurrence} ->
      event = %{
        enactment_id: state.enactment_id,
        markings: markings,
        workitem: workitem,
        occurrence: occurrence,
        binding: workitem.binding_element.binding
      }

      LifecycleHooks.safe_invoke(hooks, :on_workitem_completed, [event])
    end)
  end

  def dispatch(:withdraw_workitems, %Enactment{lifecycle_hooks: hooks} = state, %{
        workitems: workitems
      })
      when is_list(workitems) do
    markings = markings_snapshot(state)

    Enum.each(workitems, fn workitem ->
      event = %{
        enactment_id: state.enactment_id,
        markings: markings,
        workitem: workitem,
        binding: workitem.binding_element.binding
      }

      LifecycleHooks.safe_invoke(hooks, :on_workitem_withdrawn, [event])
    end)
  end

  def dispatch(_event, _state, _metadata), do: :ok

  defp markings_snapshot(%Enactment{markings: markings}) do
    Map.new(markings, fn {place, %Marking{tokens: tokens}} -> {place, tokens} end)
  end
end
