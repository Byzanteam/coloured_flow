defmodule ColouredFlow.Runner.Storage.InMemory do
  @moduledoc """
  In-memory storage for the runner.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Enactment.Workitem

  require Logger

  import Record, only: [is_record: 2]

  use TypedStructor

  typed_structor type_name: :flow,
                 definer: :defrecord,
                 record_name: :flow,
                 enforce: true do
    field :id, Ecto.UUID.t()
    field :definition, ColouredPetriNet.t()
  end

  typed_structor type_name: :enactment,
                 definer: :defrecord,
                 record_name: :enactment,
                 enforce: true do
    field :id, Ecto.UUID.t()
    field :flow_id, Ecto.UUID.t()
    field :initial_markings, [Marking.t()], default: []
  end

  typed_structor type_name: :workitem,
                 definer: :defrecord,
                 record_name: :workitem,
                 enforce: true do
    field :id, Ecto.UUID.t()
    field :enactment_id, Ecto.UUID.t()
    field :state, Workitem.state()
    field :binding_element, BindingElement.t()
  end

  typed_structor type_name: :occurrence,
                 definer: :defrecord,
                 record_name: :occurrence,
                 enforce: true do
    field :workitem_id, Ecto.UUID.t()
    field :enactment_id, Ecto.UUID.t()
    field :step_number, pos_integer()
    field :data, Occurrence.t()
  end

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec insert_flow!(ColouredPetriNet.t()) :: flow()
  def insert_flow!(%ColouredPetriNet{} = definition) do
    flow = flow(id: Ecto.UUID.generate(), definition: definition)

    insert_new(:flow, flow)
  end

  @spec insert_enactment!(flow(), initial_markings :: [Marking.t()]) :: enactment()
  def insert_enactment!(flow, initial_markings) when is_record(flow, :flow) do
    enactment =
      enactment(
        id: Ecto.UUID.generate(),
        flow_id: flow(flow, :id),
        initial_markings: initial_markings
      )

    insert_new(:enactment, enactment)
  end

  use GenServer

  @impl GenServer
  def init(_init_arg) do
    options = [:set, :protected, :named_table, {:keypos, 2}]

    tables =
      for table_name <- ~w[flow enactment workitem occurrence]a do
        {table_name, :ets.new(table(table_name), options)}
      end

    {:ok, tables}
  end

  @impl GenServer
  def handle_call({:insert_new, {table_name, items}}, _from, state) do
    true = :ets.insert_new(Keyword.fetch!(state, table_name), items)

    {:reply, items, state}
  end

  def handle_call({:update, {table_name, key, value}}, _from, state) do
    {:ok, old} = fetch(table_name, key)
    table = Keyword.fetch!(state, table_name)
    1 = :ets.select_replace(table, [{old, [], [{:const, value}]}])

    {:reply, value, state}
  end

  def handle_call({:delete, {table_name, key}}, _from, state) do
    true = :ets.delete(Keyword.fetch!(state, table_name), key)

    {:reply, :ok, state}
  end

  alias ColouredFlow.Runner.Storage

  @behaviour Storage

  @impl Storage
  def get_flow_by_enactment(enactment_id) do
    with {:ok, enactment} <- fetch(:enactment, enactment_id),
         flow_id = enactment(enactment, :flow_id),
         {:ok, flow} <- fetch(:flow, flow_id) do
      flow(flow, :definition)
    else
      {:error, :not_found, opts} -> not_found!(opts)
    end
  end

  @impl Storage
  def get_initial_markings(enactment_id) do
    case fetch(:enactment, enactment_id) do
      {:ok, enactment} -> enactment(enactment, :initial_markings)
      {:error, :not_found, opts} -> not_found!(opts)
    end
  end

  @impl Storage
  def occurrences_stream(enactment_id, from) do
    ms = [
      {
        occurrence(
          workitem_id: ignore_pos(),
          enactment_id: enactment_id,
          step_number: match_pos(1),
          data: match_pos(2)
        ),
        [{:>, match_pos(1), from}],
        [match_obj()]
      }
    ]

    :occurrence
    |> select(ms)
    |> Enum.sort_by(&occurrence(&1, :step_number))
    |> Enum.map(&occurrence(&1, :data))
  end

  @impl Storage
  def exception_occurs(enactment_id, reason, exception) do
    Logger.debug("""
    An exception occurs in the enactment with the ID #{inspect(enactment_id)}.
    Reason: #{inspect(reason)}
    Exception: #{inspect(exception)}
    """)
  end

  @impl Storage
  def terminate_enactment(enactment_id, type, final_markings, options) do
    Logger.debug("""
    The enactment with the ID #{inspect(enactment_id)} is terminated with the type #{inspect(type)}.
    Final markings: #{inspect(final_markings)}
    Options: #{inspect(options)}
    """)
  end

  @impl Storage
  def list_live_workitems(enactment_id) do
    ms = [
      {
        workitem(
          id: match_pos(1),
          enactment_id: enactment_id,
          state: match_pos(2),
          binding_element: match_pos(3)
        ),
        [in_op(2, Workitem.__live_states__())],
        [
          %Workitem{
            id: match_pos(1),
            state: match_pos(2),
            binding_element: match_pos(3)
          }
        ]
      }
    ]

    select(:workitem, ms)
  end

  @impl Storage
  def produce_workitems(enactment_id, binding_elements) do
    binding_elements
    |> Enum.map(fn binding_element ->
      workitem(
        id: Ecto.UUID.generate(),
        enactment_id: enactment_id,
        state: :enabled,
        binding_element: binding_element
      )
    end)
    |> then(&insert_new(:workitem, &1))
    |> Enum.map(
      &%Workitem{
        id: workitem(&1, :id),
        state: workitem(&1, :state),
        binding_element: workitem(&1, :binding_element)
      }
    )
  end

  @impl Storage
  def start_workitems(started_workitems, _options) do
    Enum.each(started_workitems, fn %Workitem{state: :started} = workitem ->
      {:ok, old} = fetch(:workitem, workitem.id)
      new = workitem(old, state: workitem.state)

      update(:workitem, workitem.id, new)
    end)
  end

  @impl Storage
  def withdraw_workitems(withdrawn_workitems, _options) do
    Enum.each(withdrawn_workitems, fn %Workitem{} = workitem ->
      delete(:workitem, workitem.id)
    end)
  end

  @impl Storage
  def complete_workitems(enactment_id, current_version, workitem_occurrences, _options) do
    workitem_occurrences
    |> Enum.map_reduce(
      current_version + 1,
      fn {%Workitem{} = workitem, %Occurrence{} = occurrence}, version ->
        item =
          occurrence(
            workitem_id: workitem.id,
            enactment_id: enactment_id,
            step_number: version,
            data: occurrence
          )

        {item, version + 1}
      end
    )
    |> elem(0)
    |> then(&insert_new(:occurrence, &1))

    :ok
  end

  @impl Storage
  def take_enactment_snapshot(_enactment_id, _snapshot) do
    # we don't take snapshots in the in-memory storage
    :ok
  end

  @impl Storage
  def read_enactment_snapshot(_enactment_id) do
    # cause we don't take snapshots in the in-memory storage
    :error
  end

  defp table(table_name)
  defp table(:flow), do: __MODULE__.Flow
  defp table(:enactment), do: __MODULE__.Enactment
  defp table(:workitem), do: __MODULE__.Workitem
  defp table(:occurrence), do: __MODULE__.Occurrence

  defp fetch(table_name, pk) do
    case :ets.lookup(table(table_name), pk) do
      [item] -> {:ok, item}
      [] -> {:error, :not_found, table_name: table_name, pk: pk}
    end
  end

  defp select(table_name, ms) do
    :ets.select(table(table_name), ms)
  end

  defp insert_new(table_name, items) do
    GenServer.call(__MODULE__, {:insert_new, {table_name, items}})
  end

  defp update(table_name, key, value) do
    GenServer.call(__MODULE__, {:update, {table_name, key, value}})
  end

  defp delete(table_name, key) do
    GenServer.call(__MODULE__, {:delete, {table_name, key}})
  end

  defp not_found!(opts) do
    table_name = Keyword.fetch!(opts, :table_name)
    pk = Keyword.fetch!(opts, :pk)

    raise """
    The #{table_name} with the primary key #{inspect(pk)} is not found.
    """
  end

  # ETS match spec helpers

  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp match_pos(i) when is_integer(i), do: :"$#{i}"
  defp ignore_pos, do: :_
  defp match_obj, do: :"$_"

  defp in_op(pos, [item]), do: {:"=:=", match_pos(pos), item}

  defp in_op(pos, [item | rest]) do
    {:orelse, in_op(pos, [item]), in_op(pos, rest)}
  end
end
