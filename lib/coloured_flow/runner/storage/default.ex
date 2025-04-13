defmodule ColouredFlow.Runner.Storage.Default do
  @moduledoc """
  The default storage for the coloured_flow runner. It uses Ecto to interact with the database.
  """

  @behaviour ColouredFlow.Runner.Storage

  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas

  import Ecto.Query

  @type enactment_id() :: ColouredFlow.Runner.Storage.enactment_id()
  @type flow_id() :: ColouredFlow.Runner.Storage.flow_id()

  @impl ColouredFlow.Runner.Storage
  def get_flow_by_enactment(enactment_id) do
    Schemas.Flow
    |> join(:inner, [f], e in Schemas.Enactment, on: f.id == e.flow_id)
    |> where([f, e], e.id == ^enactment_id)
    |> Repo.one!()
    |> Schemas.Flow.to_coloured_petri_net()
  end

  @impl ColouredFlow.Runner.Storage
  def get_initial_markings(enactment_id) do
    enactment = Repo.get!(Schemas.Enactment, enactment_id)

    Schemas.Enactment.to_initial_markings(enactment)
  end

  @batch 100

  @impl ColouredFlow.Runner.Storage
  def occurrences_stream(enactment_id, from) do
    fn -> from end
    |> Stream.resource(
      fn
        :end_of_stream ->
          {:halt, :end_of_stream}

        last_step_number when is_integer(last_step_number) ->
          occurrences =
            Schemas.Occurrence
            |> where([o], o.enactment_id == ^enactment_id and o.step_number > ^last_step_number)
            |> order_by(asc: :step_number)
            |> limit(@batch)
            |> Repo.all()

          {length, last_step_number} =
            Enum.reduce(
              occurrences,
              {0, last_step_number},
              fn occurrence, {length, _step_number} ->
                {length + 1, occurrence.step_number}
              end
            )

          if length === @batch do
            {occurrences, last_step_number}
          else
            {occurrences, :end_of_stream}
          end
      end,
      fn :end_of_stream -> :ok end
    )
    |> Stream.map(&Schemas.Occurrence.to_occurrence/1)
  end

  exception_reasons = ColouredFlow.Runner.Exception.__reasons__()

  @impl ColouredFlow.Runner.Storage
  def exception_occurs(enactment_id, reason, exception)
      when reason in unquote(exception_reasons) and is_exception(exception) do
    Ecto.Multi.new()
    |> Ecto.Multi.one(:enactment, fn _changes ->
      where(Schemas.Enactment, id: ^enactment_id)
    end)
    |> Ecto.Multi.update(:update_enactment, fn %{enactment: enactment} ->
      Ecto.Changeset.change(enactment, state: :exception)
    end)
    |> Ecto.Multi.insert(:insert_enactment_log, fn %{enactment: enactment} ->
      Schemas.EnactmentLog.build_exception(enactment, reason, exception)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :ok

      {:error, failed_operation, failed_value, changes_so_far} ->
        raise """
        Failed to update the enactment to exception state.

        Failed operation: #{inspect(failed_operation)}
        Failed value: #{inspect(failed_value)}
        Changes so far: #{inspect(changes_so_far)}
        """
    end
  end

  termination_types = ColouredFlow.Runner.Termination.__types__()
  @impl ColouredFlow.Runner.Storage
  def terminate_enactment(enactment_id, type, final_markings, options)
      when type in unquote(termination_types) do
    Ecto.Multi.new()
    |> Ecto.Multi.one(:enactment, fn _changes ->
      where(Schemas.Enactment, id: ^enactment_id)
    end)
    |> Ecto.Multi.update(:update_enactment, fn %{enactment: enactment} ->
      enactment
      |> Ecto.Changeset.change(state: :terminated)
      |> Ecto.Changeset.change(final_markings: final_markings)
    end)
    |> Ecto.Multi.insert(:insert_enactment_log, fn %{enactment: enactment} ->
      Schemas.EnactmentLog.build_termination(enactment, type, options)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :ok

      {:error, failed_operation, failed_value, changes_so_far} ->
        raise """
        Failed to update the enactment to terminated state.

        Failed operation: #{inspect(failed_operation)}
        Failed value: #{inspect(failed_value)}
        Changes so far: #{inspect(changes_so_far)}
        """
    end
  end

  @live_states Workitem.__live_states__()

  @impl ColouredFlow.Runner.Storage
  def list_live_workitems(enactment_id) do
    Schemas.Workitem
    |> where([wi], wi.enactment_id == ^enactment_id and wi.state in @live_states)
    |> Repo.all()
    |> Enum.map(&Schemas.Workitem.to_workitem/1)
  end

  @impl ColouredFlow.Runner.Storage
  def produce_workitems(enactment_id, binding_elements) do
    workitems =
      Enum.map(binding_elements, fn binding_element ->
        %{
          enactment_id: enactment_id,
          state: :enabled,
          binding_element: binding_element,
          inserted_at: {:placeholder, :now},
          updated_at: {:placeholder, :now}
        }
      end)

    Schemas.Workitem
    # TODO: insert workitem logs
    |> Repo.insert_all(workitems,
      returning: true,
      placeholders: %{now: DateTime.utc_now()}
    )
    |> elem(1)
    |> Enum.map(&Schemas.Workitem.to_workitem/1)
  end

  @typep transition_option() :: ColouredFlow.Runner.Storage.transition_option()

  @doc """
  Transition a workitem from one state to another.
  This is a shortcut for `ColouredFlow.Runner.Default.transition_workitems/2`.
  """
  @spec transition_workitem(Workitem.t(), [transition_option()]) :: :ok
  def transition_workitem(workitem, options) do
    workitem
    |> List.wrap()
    |> transition_workitems(options)
  end

  @doc """
  Transition the workitems from one state to another in accordance with the state machine (See `t:ColouredFlow.Runner.Enactment.Workitem.state/0`).
  """
  @spec transition_workitems([Workitem.t()], [transition_option()]) :: :ok
  def transition_workitems([], _options), do: :ok

  def transition_workitems(workitems, options) when is_list(workitems) do
    action = Keyword.fetch!(options, :action)

    workitems
    |> update_all_multi(action)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :ok

      {
        :error,
        :result,
        {:unexpected_updated_rows, exception_ctx},
        _changes_so_far
      } ->
        unexpected_updated_rows!(workitems, action, exception_ctx)
    end
  end

  # Operations
  # `:update` returns {updated_rows, nil}
  # `:result` returns:
  #     - `:ok`
  #     - `{:error, {:unexpected_updated_rows, [expected: pos_integer(), actual: pos_integer()]}}`
  @spec update_all_multi([Workitem.t()], Workitem.transition_action()) :: Ecto.Multi.t()
  defp update_all_multi([%Workitem{state: state} | _rest] = workitems, action) do
    from_state = get_from_state(state, action)

    {ids, expected_length} =
      Enum.map_reduce(
        workitems,
        0,
        fn workitem, acc -> {workitem.id, acc + 1} end
      )

    now = DateTime.utc_now()

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :update,
      Schemas.Workitem
      |> where([wi], wi.id in ^ids and wi.state == ^from_state)
      |> select([wi], wi),
      set: [state: state, updated_at: now]
    )
    |> Ecto.Multi.run(:result, fn _repo, %{update: update} ->
      case update do
        {^expected_length, _workitems} ->
          {:ok, :ok}

        {actual, _workitems} ->
          {:error, {:unexpected_updated_rows, expected: expected_length, actual: actual}}
      end
    end)
    |> Ecto.Multi.insert_all(
      :workitem_logs,
      Schemas.WorkitemLog,
      fn %{update: {_length, workitems}} ->
        Enum.map(workitems, fn %Schemas.Workitem{} = workitem ->
          %{
            workitem_id: workitem.id,
            enactment_id: workitem.enactment_id,
            from_state: {:placeholder, :from_state},
            to_state: {:placeholder, :to_state},
            action: action,
            inserted_at: {:placeholder, :now}
          }
        end)
      end,
      placeholders: %{now: now, from_state: from_state, to_state: state}
    )
  end

  defp get_from_state(to_state, action)

  defp get_from_state(%Workitem{} = workitem, action) do
    get_from_state(workitem.state, action)
  end

  for {from, action, to} <- Workitem.__transitions__() do
    defp get_from_state(unquote(to), unquote(action)), do: unquote(from)
  end

  defp unexpected_updated_rows!(workitems, transition, options) do
    # When the actual number is not equal to the expected number,
    # it means the workitems in the gen_server are not consistent with the database.
    # So we just raise an error to crash the process, and let the supervisor
    # restart the gen_server and retry.
    expected = Keyword.fetch!(options, :expected)
    actual = Keyword.fetch!(options, :actual)

    raise """
    The number of workitems to #{transition} is not equal to the actual number.
    Expected: #{expected}, Actual: #{actual}
    Workitems: #{Enum.map_join(workitems, ", ", & &1.id)}
    """
  end

  @impl ColouredFlow.Runner.Storage
  def start_workitems(workitems, options) do
    transition_workitems(workitems, options)
  end

  @impl ColouredFlow.Runner.Storage
  def withdraw_workitems(workitems, options) do
    transition_workitems(workitems, options)
  end

  @impl ColouredFlow.Runner.Storage
  def complete_workitems(enactment_id, current_version, workitem_occurrences, options) do
    action = Keyword.fetch!(options, :action)
    completed_workitems = Enum.map(workitem_occurrences, &elem(&1, 0))

    occurrence_entries = build_occurrence_entries(workitem_occurrences, current_version)

    completed_workitems
    |> update_all_multi(action)
    |> Ecto.Multi.put(:occurrence_entries, occurrence_entries)
    |> Ecto.Multi.insert_all(
      :occurrences,
      Schemas.Occurrence,
      fn %{occurrence_entries: occurrence_entries} -> occurrence_entries end,
      placeholders: %{
        enactment_id: enactment_id,
        now: DateTime.utc_now()
      }
    )
    |> Repo.transaction()
    |> case do
      {:ok, _result} ->
        :ok

      {
        :error,
        :result,
        {:unexpected_updated_rows, exception_ctx},
        _changes_so_far
      } ->
        unexpected_updated_rows!(completed_workitems, action, exception_ctx)
    end
  end

  @spec build_occurrence_entries(
          workitem_occurrences :: Enumerable.t({Workitem.t(:started), Occurrence.t()}),
          current_version :: non_neg_integer()
        ) :: [Occurrence.t()]
  defp build_occurrence_entries(workitem_occurrences, current_version) do
    workitem_occurrences
    |> Enum.map_reduce(
      current_version,
      fn {workitem, occurrence}, last_version ->
        version = last_version + 1

        {
          %{
            enactment_id: {:placeholder, :enactment_id},
            workitem_id: workitem.id,
            step_number: version,
            occurrence: occurrence,
            inserted_at: {:placeholder, :now}
          },
          version
        }
      end
    )
    |> elem(0)
  end

  @impl ColouredFlow.Runner.Storage
  def take_enactment_snapshot(enactment_id, snapshot) do
    %Schemas.Snapshot{enactment_id: enactment_id}
    |> Ecto.Changeset.change(
      version: snapshot.version,
      markings: snapshot.markings
    )
    |> Repo.insert!(
      conflict_target: [:enactment_id],
      on_conflict: {:replace_all_except, [:inserted_at]},
      returning: true
    )

    :ok
  end

  @impl ColouredFlow.Runner.Storage
  def read_enactment_snapshot(enactment_id) do
    Schemas.Snapshot
    |> Repo.get_by(enactment_id: enactment_id)
    |> case do
      nil -> :error
      snapshot -> {:ok, Schemas.Snapshot.to_snapshot(snapshot)}
    end
  end
end
