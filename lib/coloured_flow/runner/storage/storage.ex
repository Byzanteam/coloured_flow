defmodule ColouredFlow.Runner.Storage do
  @moduledoc """
  The storage for the coloured_flow runner.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas

  import Ecto.Query

  @type enactment_id() :: Ecto.UUID.t()
  @type flow_id() :: Ecto.UUID.t()

  @spec get_flow_by_enactment(enactment_id()) :: ColouredPetriNet.t()
  def get_flow_by_enactment(enactment_id) do
    Schemas.Flow
    |> join(:inner, [f], e in Schemas.Enactment, on: f.id == e.flow_id)
    |> where([f, e], e.id == ^enactment_id)
    |> Repo.one!()
    |> Schemas.Flow.to_coloured_petri_net()
  end

  @doc """
  Returns the initial markings for the given enactment.
  """
  @spec get_initial_markings(enactment_id()) :: [Marking.t()]
  def get_initial_markings(enactment_id) do
    enactment = Repo.get!(Schemas.Enactment, enactment_id)

    Schemas.Enactment.to_initial_markings(enactment)
  end

  @batch 100

  @doc """
  Returns a stream of occurrences for the given enactment,
  that occurred after the given `from`(exclusive) position.
  """
  @spec occurrences_stream(enactment_id(), from :: non_neg_integer()) ::
          Enumerable.t(Occurrence.t())
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

  @live_states Workitem.__live_states__()

  @doc """
  Returns a list of live workitems for the given enactment.
  """
  @spec list_live_workitems(enactment_id()) :: [Workitem.t()]
  def list_live_workitems(enactment_id) do
    Schemas.Workitem
    |> where([wi], wi.enactment_id == ^enactment_id and wi.state in @live_states)
    |> Repo.all()
    |> Enum.map(&Schemas.Workitem.to_workitem/1)
  end

  @doc """
  Produces the workitems for the given enactment.
  """
  @spec produce_workitems(enactment_id(), Enumerable.t(BindingElement.t())) :: [Workitem.t()]
  def produce_workitems(enactment_id, binding_elements) do
    workitems =
      Enum.map(binding_elements, fn binding_element ->
        %{
          enactment_id: enactment_id,
          state: :enabled,
          data: %Schemas.Workitem.Data{
            binding_element: binding_element
          },
          inserted_at: {:placeholder, :now},
          updated_at: {:placeholder, :now}
        }
      end)

    Schemas.Workitem
    |> Repo.insert_all(workitems,
      returning: true,
      placeholders: %{now: DateTime.utc_now()}
    )
    |> elem(1)
    |> Enum.map(&Schemas.Workitem.to_workitem/1)
  end

  @doc """
  Transition a workitem from one state to another.
  This is a shortcut for `ColouredFlow.Runner.Storage.transition_workitems/2`.
  """
  @spec transition_workitem(Workitem.t(), target_state :: Workitem.state()) :: Workitem.t()
  def transition_workitem(workitem, target_state) do
    workitem
    |> List.wrap()
    |> transition_workitems(target_state)
    |> hd()
  end

  @doc """
  Transition the workitems from one state to another in accordance with the state machine (See `t:ColouredFlow.Runner.Enactment.Workitem.state/0`).
  """
  @spec transition_workitems([Workitem.t()], target_state) :: [Workitem.t(target_state)]
        when target_state: Workitem.state()
  def transition_workitems([], _target_state), do: []

  valid_transitions = Enum.group_by(Workitem.__transitions__(), &elem(&1, 2), &elem(&1, 0))

  for {target_state, valid_states} <- valid_transitions do
    def transition_workitems(workitems, unquote(target_state))
        when is_list(workitems) do
      do_transition_workitems(workitems, unquote(target_state), unquote(valid_states))
    end
  end

  defp do_transition_workitems(workitems, target_state, valid_states)
       when is_list(workitems) do
    {ids, length} = check_state!(workitems, valid_states)

    case update_all(ids, length, target_state) do
      :ok ->
        Enum.map(workitems, &Map.put(&1, :state, target_state))

      {:error, {:unexpected_updated_rows, [expected: length, actual: actual]}} ->
        # When the actual number is not equal to the expected number,
        # it means the workitems in the gen_server are not consistent with the database.
        # So we just raise an error to crash the process, and let the supervisor
        # restart the gen_server and retry.
        raise """
        The number of workitems to transition to #{inspect(target_state)} is not equal to the actual number.
        Expected: #{length}, Actual: #{actual}
        Workitems: #{Enum.join(ids, ", ")}
        """
    end
  end

  @spec check_state!([Workitem.t()], [Workitem.state()]) ::
          {ids :: [Workitem.id()], length :: pos_integer()}
  defp check_state!(workitems, valid_states)
       when is_list(workitems) and is_list(valid_states) do
    Enum.map_reduce(workitems, 0, fn %Workitem{state: state} = workitem, acc ->
      if state in valid_states do
        {workitem.id, acc + 1}
      else
        raise ArgumentError,
              """
              The workitem state is not in valid states.
              Valid states: #{inspect(valid_states)}
              Workitem: #{inspect(workitem)}
              """
      end
    end)
  end

  @spec update_all(
          ids :: [Workitem.id()],
          expected_length :: pos_integer(),
          target_state :: Workitem.state()
        ) ::
          :ok
          | {
              :error,
              {:unexpected_updated_rows, [expected: pos_integer(), actual: pos_integer()]}
            }
  defp update_all(ids, expected_length, target_state) do
    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :withdraw,
      where(Schemas.Workitem, [wi], wi.id in ^ids),
      set: [state: target_state, updated_at: DateTime.utc_now()]
    )
    |> Ecto.Multi.run(:result, fn _repo, %{withdraw: withdraw} ->
      case withdraw do
        {^expected_length, nil} ->
          {:ok, :ok}

        {actual, nil} ->
          {:error, {:unexpected_updated_rows, expected: expected_length, actual: actual}}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :ok

      {:error, :result, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  @spec take_enactment_snapshot(enactment_id(), Snapshot.t()) :: :ok
  def take_enactment_snapshot(enactment_id, snapshot) do
    %Schemas.Snapshot{enactment_id: enactment_id}
    |> Ecto.Changeset.change(
      version: snapshot.version,
      data: %{markings: snapshot.markings}
    )
    |> Repo.insert!(
      conflict_target: [:enactment_id],
      on_conflict: {:replace_all_except, [:inserted_at]},
      returning: true
    )

    :ok
  end

  @spec read_enactment_snapshot(enactment_id()) :: {:ok, Snapshot.t()} | :error
  def read_enactment_snapshot(enactment_id) do
    Schemas.Snapshot
    |> Repo.get_by(enactment_id: enactment_id)
    |> case do
      nil -> :error
      snapshot -> {:ok, Schemas.Snapshot.to_snapshot(snapshot)}
    end
  end
end
