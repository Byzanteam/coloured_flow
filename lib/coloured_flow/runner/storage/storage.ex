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

  @live_states ~w[offered allocated started]a

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
          state: :offered,
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
  Withdraws the offered workitems.
  """
  @spec withdraw_workitems([Workitem.t()]) :: :ok
  def withdraw_workitems(workitems) do
    ids =
      Enum.map(workitems, fn
        %Workitem{state: state} = workitem when state in @live_states ->
          workitem.id

        %Workitem{} = workitem ->
          raise ArgumentError, "The workitem state is not `offered`: #{inspect(workitem)}"
      end)

    Schemas.Workitem
    |> where([wi], wi.id in ^ids and wi.state in @live_states)
    |> Repo.update_all(set: [state: :withdrawn])

    :ok
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
