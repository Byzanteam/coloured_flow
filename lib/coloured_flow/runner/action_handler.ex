defmodule ColouredFlow.Runner.ActionHandler do
  @moduledoc """
  Behaviour for receiving enactment- and workitem-lifecycle callbacks for a single
  running enactment.

  An action handler is registered per enactment instance via
  `ColouredFlow.Runner.Enactment.Supervisor.start_enactment/2`'s `:action_handler`
  option (or `MyWorkflow.start_enactment/2` when the workflow was defined via
  `ColouredFlow.DSL`). Telemetry events are emitted in addition and remain the
  integration surface for cross-cutting observability — the handler is the
  integration surface for *workflow-specific* side effects.

  All callbacks are optional; the runner only invokes those a handler exports.
  Callbacks run inline in the enactment GenServer process, so handlers must return
  quickly. Side effects that may block belong inside a `Task` — see
  `ColouredFlow.DSL`'s `action do ... end` macro, which wraps user code in a
  `Task.Supervisor.start_child/2` automatically.

  Exceptions raised by a handler callback are caught and discarded; the runner
  never lets a misbehaving handler stop or destabilise an enactment.
  """

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.Enactment.Workitem

  @typedoc """
  Context passed to every callback.

  Carries identifiers and a snapshot of the enactment's current markings so the
  handler can react without an extra `:sys.get_state/1` round-trip.
  """
  @type ctx() :: %{
          enactment_id: binary(),
          markings: %{Place.name() => MultiSet.t()}
        }

  @type terminate_reason() :: :implicit | :explicit | :force

  @callback on_enactment_start(ctx()) :: :ok
  @callback on_enactment_terminate(ctx(), terminate_reason()) :: :ok
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_enactment_exception(ctx(), reason :: term()) :: :ok

  @callback on_workitem_enabled(ctx(), Workitem.t(:enabled)) :: :ok
  @callback on_workitem_started(ctx(), Workitem.t(:started)) :: :ok
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_workitem_completed(ctx(), Workitem.t(:completed), Occurrence.t()) :: :ok
  @callback on_workitem_withdrawn(ctx(), Workitem.t()) :: :ok
  @callback on_workitem_reoffered(ctx(), Workitem.t(:enabled)) :: :ok

  @optional_callbacks on_enactment_start: 1,
                      on_enactment_terminate: 2,
                      on_enactment_exception: 2,
                      on_workitem_enabled: 2,
                      on_workitem_started: 2,
                      on_workitem_completed: 3,
                      on_workitem_withdrawn: 2,
                      on_workitem_reoffered: 2

  @doc false
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec safe_invoke(module() | nil, atom(), [term()]) :: :ok
  def safe_invoke(nil, _callback, _args), do: :ok

  def safe_invoke(handler, callback, args)
      when is_atom(handler) and is_atom(callback) and is_list(args) do
    if function_exported?(handler, callback, length(args)) do
      try do
        apply(handler, callback, args)
      rescue
        _exception -> :ok
      catch
        _kind, _reason -> :ok
      end
    end

    :ok
  end

  @doc false
  @spec build_ctx(enactment_id :: binary(), markings :: %{Place.name() => Marking.t()}) :: ctx()
  def build_ctx(enactment_id, markings) when is_binary(enactment_id) and is_map(markings) do
    %{
      enactment_id: enactment_id,
      markings: Map.new(markings, fn {place, %Marking{tokens: tokens}} -> {place, tokens} end)
    }
  end
end
