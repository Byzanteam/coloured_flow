defmodule ColouredFlow.Runner.Enactment.Listener do
  # credo:disable-for-this-file JetCredo.Checks.ExplicitAnyType
  @moduledoc """
  Behaviour for receiving enactment- and workitem-lifecycle callbacks for a single
  running enactment.

  A listener is registered per-instance via
  `ColouredFlow.Runner.Enactment.Supervisor.start_enactment/2`'s `:listener`
  option (or `MyWorkflow.start_enactment/2` when the workflow was defined via
  `ColouredFlow.DSL`). Telemetry events are emitted in addition and remain the
  integration surface for cross-cutting observability — the listener is the
  integration surface for *workflow-specific* side effects.

  ## Listener value shapes

  The runner accepts:

  - `module` — calls `module.callback(args..., nil)` on each lifecycle event.
  - `{module, extras}` — calls `module.callback(args..., extras)`. Use this to
    inject per-instance configuration (a Phoenix.PubSub topic prefix, a
    Task.Supervisor name, …) into otherwise-static callback code.
  - `nil` — no listener bound, lifecycle dispatch is a no-op.

  Any other value (a PID, string, mis-shaped tuple, …) is silently ignored by
  `safe_invoke/3`; the runner promises a misbehaving listener never destabilises
  the enactment.

  All callbacks are optional; the runner only invokes those a listener exports at
  the right arity. Callbacks run inline in the enactment GenServer process, so
  listeners must return quickly. Side effects that may block belong inside a
  `Task` — see `ColouredFlow.DSL`'s `action do ... end` macro, which wraps user
  code in a `Task.Supervisor.start_child/2` automatically.

  Exceptions raised by a callback are caught and discarded; the runner never lets
  a misbehaving listener stop or destabilise an enactment.
  """

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.Enactment.Workitem

  @typedoc """
  Context passed to every callback. Carries identifiers and a snapshot of the
  enactment's current markings so the listener can react without an extra
  `:sys.get_state/1` round-trip.
  """
  @type ctx() :: %{
          enactment_id: binary(),
          markings: %{Place.name() => MultiSet.t()}
        }

  @type terminate_reason() :: :implicit | :explicit | :force

  @typedoc """
  Listener value. See module doc for the three accepted shapes.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @type t() :: module() | {module(), extras :: term()} | nil

  @doc """
  Fires once after the enactment GenServer finishes booting (snapshot recovery +
  initial calibration). At call time `ctx.markings` reflects any workitems
  produced or withdrawn during the boot.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_enactment_start(ctx(), extras :: term()) :: :ok

  @doc """
  Fires when the enactment terminates normally. `reason` is one of `:implicit`,
  `:explicit`, `:force`.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_enactment_terminate(ctx(), reason :: terminate_reason(), extras :: term()) :: :ok

  @doc """
  Fires when the runner records an exception against the enactment.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_enactment_exception(ctx(), reason :: term(), extras :: term()) :: :ok

  @doc """
  Fires when a workitem becomes `:enabled` after calibration.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_workitem_enabled(ctx(), Workitem.t(:enabled), extras :: term()) :: :ok

  @doc """
  Fires when a workitem transitions `:enabled → :started`.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_workitem_started(ctx(), Workitem.t(:started), extras :: term()) :: :ok

  @doc """
  Fires when a workitem transitions `:started → :completed` and the firing
  occurrence has been applied to `state.markings`.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_workitem_completed(
              ctx(),
              Workitem.t(:completed),
              Occurrence.t(),
              extras :: term()
            ) :: :ok

  @doc """
  Fires when a workitem is withdrawn (concurrent firing consumed its tokens or the
  user explicitly withdrew it).
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback on_workitem_withdrawn(ctx(), Workitem.t(), extras :: term()) :: :ok

  @optional_callbacks on_enactment_start: 2,
                      on_enactment_terminate: 3,
                      on_enactment_exception: 3,
                      on_workitem_enabled: 3,
                      on_workitem_started: 3,
                      on_workitem_completed: 4,
                      on_workitem_withdrawn: 3

  @doc false
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec safe_invoke(t(), atom(), [term()]) :: :ok
  def safe_invoke(nil, _callback, _args), do: :ok

  def safe_invoke({module, extras}, callback, args)
      when is_atom(module) and is_atom(callback) and is_list(args) do
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    do_invoke(module, callback, args ++ [extras])
  end

  def safe_invoke(module, callback, args)
      when is_atom(module) and is_atom(callback) and is_list(args) do
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    do_invoke(module, callback, args ++ [nil])
  end

  # Malformed listener value (PID, string, mis-shaped tuple, …). The runner
  # promises a misbehaving listener never destabilises the enactment, so
  # silently drop the call rather than letting `FunctionClauseError` bubble.
  def safe_invoke(_other, _callback, _args), do: :ok

  defp do_invoke(module, callback, full_args) do
    if function_exported?(module, callback, length(full_args)) do
      try do
        apply(module, callback, full_args)
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
