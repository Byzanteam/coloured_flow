defmodule ColouredFlow.Runner.Enactment.LifecycleHooks do
  @moduledoc """
  Behaviour for receiving enactment- and workitem-lifecycle callbacks for a single
  running enactment.

  A hook module is registered per-instance via
  `ColouredFlow.Runner.Enactment.Supervisor.start_enactment/2`'s
  `:lifecycle_hooks` option (or `MyWorkflow.start_enactment/2` when the workflow
  was defined via `ColouredFlow.DSL`). Telemetry events are emitted in addition
  and remain the integration surface for cross-cutting observability — lifecycle
  hooks are the integration surface for *workflow-specific* side effects.

  ## Hook value shapes

  The runner accepts:

  - `module` — calls `module.callback(event, [])` on each lifecycle event.
  - `{module, options}` — calls `module.callback(event, options)`. Use this to
    inject per-instance configuration (a Phoenix.PubSub topic prefix, a
    Task.Supervisor name, …) into otherwise-static callback code. `options` must
    be a keyword list.
  - `nil` — no hooks bound, lifecycle dispatch is a no-op.

  Any other value (a PID, string, mis-shaped tuple, …) is rejected with an
  `ArgumentError` at `start_link/1` time, before the GenServer is spawned.

  Each callback receives a typed event map and the `options` keyword. All
  callbacks are optional; the runner only invokes those a hook module exports at
  the right arity. Callbacks run inline in the enactment GenServer process, so
  hooks must return quickly. Side effects that may block belong inside a `Task` —
  see `ColouredFlow.DSL`'s `action do ... end` macro, which wraps user code in a
  `Task.Supervisor.start_child/2` automatically.

  Exceptions raised by a callback are caught and discarded; the runner never lets
  a misbehaving hook stop or destabilise an enactment.
  """

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.MultiSet
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Exception
  alias ColouredFlow.Runner.Storage

  @typedoc """
  Snapshot of the enactment's current markings — a map from place name to the
  multiset of tokens currently held on that place.
  """
  @type markings() :: %{Place.name() => MultiSet.t()}

  @typedoc """
  Per-instance options keyword list. Populated from the second element of the
  `{module, options}` tuple, or `[]` when the hook is registered as a bare module.
  """
  @type options() :: keyword()

  @typedoc """
  Lifecycle hooks value. See module doc for the three accepted shapes. Stored on
  `Runner.Enactment` state in normalised form: either `{module, keyword}` or
  `nil`.
  """
  @type t() :: {module(), options()} | nil

  @typedoc "Reason value passed to `on_enactment_terminate/2`."
  @type terminate_reason() :: :implicit | :explicit | :force

  @typedoc "Reason value passed to `on_enactment_exception/2`."
  @type exception_reason() :: Storage.ensure_runnable_error() | Exception.reason()

  @type enactment_start_event() :: %{
          enactment_id: binary(),
          markings: markings()
        }

  @type enactment_terminate_event() :: %{
          enactment_id: binary(),
          markings: markings(),
          reason: terminate_reason()
        }

  @type enactment_exception_event() :: %{
          enactment_id: binary(),
          markings: markings(),
          reason: exception_reason()
        }

  @type workitem_enabled_event() :: %{
          enactment_id: binary(),
          markings: markings(),
          workitem: Workitem.t(:enabled),
          binding: keyword()
        }

  @type workitem_started_event() :: %{
          enactment_id: binary(),
          markings: markings(),
          workitem: Workitem.t(:started),
          binding: keyword()
        }

  @type workitem_completed_event() :: %{
          enactment_id: binary(),
          markings: markings(),
          workitem: Workitem.t(:completed),
          occurrence: Occurrence.t(),
          binding: keyword()
        }

  @type workitem_withdrawn_event() :: %{
          enactment_id: binary(),
          markings: markings(),
          workitem: Workitem.t(),
          binding: keyword()
        }

  @doc """
  Fires once after the enactment GenServer finishes booting (snapshot recovery +
  initial calibration). At call time `event.markings` reflects any workitems
  produced or withdrawn during the boot.
  """
  @callback on_enactment_start(enactment_start_event(), options()) :: :ok

  @doc """
  Fires when the enactment terminates normally. `event.reason` is one of
  `:implicit`, `:explicit`, `:force`.
  """
  @callback on_enactment_terminate(enactment_terminate_event(), options()) :: :ok

  @doc """
  Fires when the runner records an exception against the enactment.
  """
  @callback on_enactment_exception(enactment_exception_event(), options()) :: :ok

  @doc """
  Fires when a workitem becomes `:enabled` after calibration.
  """
  @callback on_workitem_enabled(workitem_enabled_event(), options()) :: :ok

  @doc """
  Fires when a workitem transitions `:enabled → :started`.
  """
  @callback on_workitem_started(workitem_started_event(), options()) :: :ok

  @doc """
  Fires when a workitem transitions `:started → :completed` and the firing
  occurrence has been applied to `state.markings`.
  """
  @callback on_workitem_completed(workitem_completed_event(), options()) :: :ok

  @doc """
  Fires when a workitem is withdrawn (concurrent firing consumed its tokens or the
  user explicitly withdrew it).
  """
  @callback on_workitem_withdrawn(workitem_withdrawn_event(), options()) :: :ok

  @optional_callbacks on_enactment_start: 2,
                      on_enactment_terminate: 2,
                      on_enactment_exception: 2,
                      on_workitem_enabled: 2,
                      on_workitem_started: 2,
                      on_workitem_completed: 2,
                      on_workitem_withdrawn: 2

  @doc false
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec validate!(term()) :: t()
  def validate!(nil), do: nil
  def validate!(module) when is_atom(module), do: {module, []}

  def validate!({module, options}) when is_atom(module) and is_list(options) do
    if Keyword.keyword?(options) do
      {module, options}
    else
      raise ArgumentError,
            ":lifecycle_hooks options must be a keyword list, got: " <> inspect(options)
    end
  end

  def validate!(other) do
    raise ArgumentError,
          ":lifecycle_hooks must be a module, `{module, keyword}`, or `nil`; got: " <>
            inspect(other)
  end

  @doc false
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec safe_invoke(t(), atom(), [term()]) :: :ok
  def safe_invoke(nil, _callback, _args), do: :ok

  def safe_invoke({module, options}, callback, args)
      when is_atom(module) and is_atom(callback) and is_list(args) and is_list(options) do
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    do_invoke(module, callback, args ++ [options])
  end

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
end
