defmodule ColouredFlow.Runner.Enactment do
  @moduledoc """
  Each process instance represents one individual enactment of the process, using its
  own process instance data, and which is (normally) capable of independent control
  and audit as it progresses towards completion or termination.
  """

  use GenServer
  use TypedStructor

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.MultiSet

  alias ColouredFlow.Runner.Enactment.Catchuping
  alias ColouredFlow.Runner.Enactment.Registry
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage

  @typep enactment_id() :: Storage.enactment_id()
  @typep workitem_id() :: Workitem.id()

  typed_structor type_name: :state, enforce: true do
    @typedoc "The state of the enactment."

    plugin TypedStructor.Plugins.DocFields

    field :enactment_id, enactment_id(), doc: "The unique identifier of this enactment."

    field :version, non_neg_integer(),
      default: 0,
      doc: "The version of the enactment, incremented on each occurrence."

    field :markings, [Marking.t()], default: [], doc: "The current markings of the enactment."
    field :workitems, [Workitem.t()], default: [], doc: "The live workitems of the enactment."
  end

  @typep init_arg() :: [enactment_id: enactment_id()]

  @spec start_link(init_arg()) :: GenServer.on_start()
  def start_link(init_arg) do
    enactment_id = Keyword.fetch!(init_arg, :enactment_id)

    GenServer.start_link(__MODULE__, init_arg,
      name: Registry.via_name({:enactment, enactment_id})
    )
  end

  @impl GenServer
  def init(init_arg) do
    state = %__MODULE__{
      enactment_id: Keyword.fetch!(init_arg, :enactment_id)
    }

    {:ok, state, {:continue, :populate_state}}
  end

  @impl GenServer
  def handle_continue(:populate_state, %__MODULE__{} = state) do
    snapshot =
      case Storage.read_enactment_snapshot(state.enactment_id) do
        {:ok, snapshot} ->
          snapshot

        :error ->
          %Snapshot{
            version: 0,
            markings: Storage.get_initial_markings(state.enactment_id)
          }
      end

    snapshot = catchup_snapshot(state.enactment_id, snapshot)
    Storage.take_enactment_snapshot(state.enactment_id, snapshot)

    workitems = Storage.list_live_workitems(state.enactment_id)

    {
      :noreply,
      %__MODULE__{
        state
        | version: snapshot.version,
          markings: snapshot.markings,
          workitems: workitems
      },
      {:continue, :calibrate_workitems}
    }
  end

  def handle_continue(:calibrate_workitems, %__MODULE__{} = state) do
    alias ColouredFlow.EnabledBindingElements.Computation

    cpnet = Storage.get_flow_by_enactment(state.enactment_id)

    binding_elements =
      cpnet.transitions
      |> Enum.flat_map(fn transition ->
        Computation.list(transition, cpnet, state.markings)
      end)
      |> MultiSet.new()

    %{to_produce: to_produce, to_withdraw: to_withdraw, existings: existings} =
      Enum.reduce(
        state.workitems,
        %{to_produce: binding_elements, to_withdraw: [], existings: []},
        fn %Workitem{} = workitem, ctx ->
          case MultiSet.pop(ctx.to_produce, workitem.binding_element) do
            {0, _binding_elements} ->
              %{ctx | to_withdraw: [workitem | ctx.to_withdraw]}

            {1, binding_elements} ->
              %{ctx | to_produce: binding_elements, existings: [workitem | ctx.existings]}
          end
        end
      )

    produced_workitems = Storage.produce_workitems(state.enactment_id, to_produce)
    _withdrawn = Storage.transition_workitems(to_withdraw, :withdrawn)

    {:noreply, %__MODULE__{state | workitems: existings ++ produced_workitems}}
  end

  @spec catchup_snapshot(enactment_id(), Snapshot.t()) :: Snapshot.t()
  defp catchup_snapshot(enactment_id, snapshot) do
    occurrences = Storage.occurrences_stream(enactment_id, snapshot.version)

    {steps, markings} = Catchuping.apply(snapshot.markings, occurrences)

    %Snapshot{snapshot | version: snapshot.version + steps, markings: markings}
  end
end
