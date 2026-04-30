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
          :exit, {:noproc, _info} ->
            {:error,
             Exceptions.EnactmentNotRunning.exception(
               enactment_id: enactment_id,
               reason: :not_started
             )}

          :exit, {:timeout, _info} ->
            {:error,
             Exceptions.EnactmentTimeout.exception(
               enactment_id: enactment_id,
               timeout: timeout
             )}

          :exit, {:shutdown, _info} ->
            {:error,
             Exceptions.EnactmentNotRunning.exception(
               enactment_id: enactment_id,
               reason: :shutting_down
             )}

          :exit, {:normal, _info} ->
            {:error,
             Exceptions.EnactmentNotRunning.exception(
               enactment_id: enactment_id,
               reason: :stopped_during_call
             )}

          :exit, {:calling_self, _info} = reason ->
            # Programming error — surface it.
            exit(reason)

          :exit, reason ->
            # Catch-all: :killed, {:nodedown, _}, or any other crash mid-call.
            {:error,
             Exceptions.EnactmentCallFailed.exception(
               enactment_id: enactment_id,
               reason: reason
             )}
        end
    end
  end
end
