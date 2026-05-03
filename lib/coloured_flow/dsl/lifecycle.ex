defmodule ColouredFlow.DSL.Lifecycle do
  @moduledoc """
  `on_enactment_start/1`, `on_enactment_terminate/{1,2}`, and
  `on_enactment_exception/{1,2}` macros.

  Each macro registers a clause that the workflow module's
  `ColouredFlow.Runner.ActionHandler` callback will execute. Bodies are wrapped in
  a task by `ColouredFlow.DSL.Builder` (using the `:task_supervisor` option passed
  to `use ColouredFlow.DSL`, falling back to an unsupervised `Task.start/1`) so
  the runner never blocks on user-defined side effects.

  Each hook may appear at most once per workflow. A second declaration raises a
  `CompileError` pointing to the offending macro call.
  """

  @doc """
  Runs once when the enactment GenServer finishes booting (after snapshot recovery
  and initial calibration). The body has access to the magic variable `ctx` — a
  map carrying `:enactment_id` and the current `:markings`.

  ## Examples

      on_enactment_start do
        Logger.info("enactment started: " <> ctx.enactment_id)
      end
  """
  defmacro on_enactment_start(do: body) do
    push_hook!(:on_enactment_start, body, __CALLER__)
  end

  defmacro on_enactment_start(body) do
    push_hook!(:on_enactment_start, normalise(body), __CALLER__)
  end

  @doc """
  Runs when the enactment terminates normally (`:implicit`, `:explicit`, or
  `:force`). The body has access to `ctx` and the magic variable `reason`, bound
  to the termination type.

  ## Examples

      on_enactment_terminate do
        Logger.info("done: " <> inspect(reason))
      end

      on_enactment_terminate reason do
        Telemetry.execute([:my_app, :workflow, :ended], %{}, %{reason: reason})
      end
  """
  defmacro on_enactment_terminate(do: body) do
    push_hook!(:on_enactment_terminate, body, __CALLER__)
  end

  defmacro on_enactment_terminate(body) do
    push_hook!(:on_enactment_terminate, normalise(body), __CALLER__)
  end

  defmacro on_enactment_terminate(_var, do: body) do
    push_hook!(:on_enactment_terminate, body, __CALLER__)
  end

  @doc """
  Runs when the runner records an exception against the enactment. Body has access
  to `ctx` and the magic variable `reason`.

  ## Examples

      on_enactment_exception reason do
        Logger.error("workflow blew up: " <> inspect(reason))
      end
  """
  defmacro on_enactment_exception(do: body) do
    push_hook!(:on_enactment_exception, body, __CALLER__)
  end

  defmacro on_enactment_exception(body) do
    push_hook!(:on_enactment_exception, normalise(body), __CALLER__)
  end

  defmacro on_enactment_exception(_var, do: body) do
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

  defp normalise([{:do, body}]), do: body
  defp normalise(body), do: body

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
