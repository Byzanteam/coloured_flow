defmodule ColouredFlow.DSL.Lifecycle do
  @moduledoc """
  `on_enactment_start/1`, `on_enactment_terminate/1`, and
  `on_enactment_exception/1` macros.

  Each macro registers a clause that the workflow module's
  `ColouredFlow.Runner.Enactment.LifecycleHooks` callback will execute. Bodies are
  wrapped in a task by `ColouredFlow.DSL.Builder` (using the `:task_supervisor`
  option passed to `use ColouredFlow.DSL`, falling back to an unsupervised
  `Task.start/1`) so the runner never blocks on user-defined side effects.

  Each hook may appear at most once per workflow. A second declaration raises a
  `CompileError` pointing to the offending macro call.

  Inside every hook body, the magic bindings `event` and `options` are available.
  `event` is the typed event map documented on each
  `ColouredFlow.Runner.Enactment.LifecycleHooks` callback (e.g.,
  `event.enactment_id`, `event.markings`, `event.reason`); `options` is the
  keyword list registered alongside the hook module via the `{module, options}`
  tuple form (or `[]` when registered as a bare module).
  """

  @doc """
  Runs once when the enactment GenServer finishes booting (after snapshot recovery
  and initial calibration). Inside the body, `event.enactment_id` and
  `event.markings` are available.

  ## Examples

      on_enactment_start do
        Logger.info("enactment started: " <> event.enactment_id)
      end
  """
  defmacro on_enactment_start(do: body) do
    push_hook!(:on_enactment_start, body, __CALLER__)
  end

  @doc """
  Runs when the enactment terminates normally. Inside the body, `event.reason` is
  one of `:implicit`, `:explicit`, `:force`.

  ## Examples

      on_enactment_terminate do
        Logger.info("done: " <> inspect(event.reason))
      end
  """
  defmacro on_enactment_terminate(do: body) do
    push_hook!(:on_enactment_terminate, body, __CALLER__)
  end

  @doc """
  Runs when the runner records an exception against the enactment. Inside the
  body, `event.reason` carries the failure mode (e.g., `:abnormal_exit`,
  `:snapshot_corrupt`, `:invalid_termination_criteria`,
  `:crash_threshold_exceeded`, `:terminated`, `:already_in_exception`).

  ## Examples

      on_enactment_exception do
        Logger.error("workflow blew up: " <> inspect(event.reason))
      end
  """
  defmacro on_enactment_exception(do: body) do
    push_hook!(:on_enactment_exception, body, __CALLER__)
  end

  defp push_hook!(kind, body, caller) do
    file = caller.file
    line = caller.line
    escaped_body = Macro.escape(body)

    quote do
      ColouredFlow.DSL.Lifecycle.__push_hook__!(
        __MODULE__,
        unquote(kind),
        unquote(escaped_body),
        unquote(file),
        unquote(line)
      )
    end
  end

  @doc false
  @spec __push_hook__!(module(), atom(), Macro.t(), String.t(), non_neg_integer()) :: :ok
  def __push_hook__!(module, kind, body, file, line) do
    existing = Module.get_attribute(module, :cf_lifecycle_hooks) || []

    if Enum.any?(existing, fn {existing_kind, _body} -> existing_kind == kind end) do
      raise CompileError,
        description: "#{kind} already declared in this workflow",
        file: file,
        line: line
    end

    Module.put_attribute(module, :cf_lifecycle_hooks, {kind, body})
    :ok
  end
end
