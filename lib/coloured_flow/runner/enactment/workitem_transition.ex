defmodule ColouredFlow.Runner.Enactment.WorkitemTransition do
  @moduledoc """
  Workitem transition functions, which are dispatched to the corresponding
  enactment gen_server.

  All public functions in this module funnel `GenServer.call/3` through a
  caller-safe wrapper that translates the full `:exit` surface (`:noproc`,
  `:timeout`, `:nodedown`, `:shutdown`, `:normal`, `:killed`, ...) into typed
  exceptions returned via `{:error, exception}`. Callers therefore never have to
  handle raw process-exit signals.
  """

  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage

  @typep enactment_id() :: Storage.enactment_id()
  @typep workitem_id() :: Workitem.id()

  @call_timeout 5_000

  @spec start_workitem(enactment_id(), workitem_id()) ::
          {:ok, Workitem.t(:started)} | {:error, Exception.t()}
  def start_workitem(enactment_id, workitem_id) do
    case start_workitems(enactment_id, [workitem_id]) do
      {:ok, [workitem]} -> {:ok, workitem}
      {:error, _exception} = error -> error
    end
  end

  @spec start_workitems(enactment_id(), [workitem_id()]) ::
          {:ok, [Workitem.t(:started)]} | {:error, Exception.t()}
  def start_workitems(enactment_id, workitem_ids) when is_list(workitem_ids) do
    call_enactment(enactment_id, {:start_workitems, workitem_ids})
  end

  @spec complete_workitem(
          enactment_id(),
          workitem_id_and_outputs :: {workitem_id(), Occurrence.free_binding()}
        ) :: {:ok, Workitem.t(:completed)} | {:error, Exception.t()}
  def complete_workitem(enactment_id, {workitem_id, outputs}) do
    case complete_workitems(enactment_id, [{workitem_id, outputs}]) do
      {:ok, [workitem]} -> {:ok, workitem}
      {:error, _exception} = error -> error
    end
  end

  @spec complete_workitems(
          enactment_id(),
          Enumerable.t({workitem_id(), Occurrence.free_binding()})
        ) :: {:ok, [Workitem.t(:completed)]} | {:error, Exception.t()}
  def complete_workitems(enactment_id, workitem_id_and_outputs_list) do
    call_enactment(enactment_id, {:complete_workitems, workitem_id_and_outputs_list})
  end

  @doc """
  Caller-safe wrapper around `GenServer.call/3` against an enactment's via name.

  Returns the GenServer reply unchanged on success (`{:ok, _}` or `{:error, _}`),
  or normalises any `:exit` from a missing/dying/timing-out process into a typed
  exception returned via `{:error, exception}`. The full exit surface is
  enumerated below; unknown exit reasons fall through to `EnactmentCallFailed`.
  """
  # credo:disable-for-lines:2 JetCredo.Checks.ExplicitAnyType
  @spec call_enactment(enactment_id(), term(), timeout()) ::
          term() | {:error, Exception.t()}
  def call_enactment(enactment_id, message, timeout \\ @call_timeout) do
    case Registry.whereis({:enactment, enactment_id}) do
      :error ->
        {:error,
         Exceptions.EnactmentNotRunning.exception(
           enactment_id: enactment_id,
           reason: :not_started
         )}

      {:ok, pid} ->
        try do
          GenServer.call(pid, message, timeout)
        catch
          :exit, reason ->
            classify_exit(unwrap_call_reason(reason), enactment_id, timeout)
        end
    end
  end

  # `GenServer.call/3` wraps the callee's exit reason as
  # `{reason, {GenServer, :call, [pid, message, timeout]}}` before re-exiting in
  # the caller. Unwrap so we can classify by the underlying reason alone.
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec unwrap_call_reason(term()) :: term()
  defp unwrap_call_reason({reason, {GenServer, :call, _info}}), do: reason
  defp unwrap_call_reason(reason), do: reason

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec classify_exit(term(), enactment_id(), timeout()) ::
          {:error, Exception.t()} | no_return()
  defp classify_exit(:noproc, enactment_id, _timeout) do
    {:error,
     Exceptions.EnactmentNotRunning.exception(
       enactment_id: enactment_id,
       reason: :not_started
     )}
  end

  defp classify_exit(:timeout, enactment_id, timeout) do
    {:error,
     Exceptions.EnactmentTimeout.exception(
       enactment_id: enactment_id,
       timeout: timeout
     )}
  end

  defp classify_exit(:normal, enactment_id, _timeout) do
    {:error,
     Exceptions.EnactmentNotRunning.exception(
       enactment_id: enactment_id,
       reason: :stopped_during_call
     )}
  end

  defp classify_exit(:shutdown, enactment_id, _timeout) do
    {:error,
     Exceptions.EnactmentNotRunning.exception(
       enactment_id: enactment_id,
       reason: :shutting_down
     )}
  end

  defp classify_exit({:shutdown, _shutdown_reason}, enactment_id, _timeout) do
    {:error,
     Exceptions.EnactmentNotRunning.exception(
       enactment_id: enactment_id,
       reason: :shutting_down
     )}
  end

  defp classify_exit(:calling_self, _enactment_id, _timeout) do
    # Programming error — surface it instead of swallowing.
    exit(:calling_self)
  end

  defp classify_exit(reason, enactment_id, _timeout) do
    # Catch-all: `:killed`, `{:nodedown, node}`, or any other crash reason.
    {:error,
     Exceptions.EnactmentCallFailed.exception(
       enactment_id: enactment_id,
       reason: reason
     )}
  end
end
