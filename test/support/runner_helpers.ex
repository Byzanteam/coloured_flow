defmodule ColouredFlow.RunnerHelpers do
  @moduledoc false

  import ColouredFlow.Factory
  import ExUnit.Callbacks

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Storage.Schemas

  defmacro __using__(_opts) do
    quote generated: true do
      alias ColouredFlow.Enactment.Marking

      alias ColouredFlow.Runner.Enactment
      alias ColouredFlow.Runner.Storage.Schemas

      import unquote(__MODULE__)
      import ColouredFlow.MultiSet, only: :sigils
    end
  end

  ## Setup helpers

  @doc """
  Setup a CPNet schema for testing.

  ## Parameters

    * `cpnet` - the name of the CPNet or a CPNet struct to setup.

  ## Returns

      * `cpnet` - the CPNet struct.

  ## Examples

        setup :setup_cpnet

        @tag cpnet: :simple_sequence
        test "message", %{cpnet: cpnet}
  """
  @spec setup_cpnet(%{cpnet: atom() | ColouredPetriNet.t()}) :: [cpnet: ColouredPetriNet.t()]
  def setup_cpnet(%{cpnet: cpnet}) when is_atom(cpnet) do
    cpnet = ColouredFlow.CpnetBuilder.build_cpnet(cpnet)

    [cpnet: cpnet]
  end

  def setup_cpnet(%{cpnet: cpnet}) when is_struct(cpnet, ColouredPetriNet) do
    [cpnet: cpnet]
  end

  @doc """
  Setup a flow schema for testing.

  ## Parameters

    * `cpnet` - the name of the CPNet or a CPNet struct to setup.

  ## Returns

      * `flow` - the flow struct.

  ## Examples

      setup :setup_flow

      @tag cpnet: :simple_sequence
      test "message", %{flow: flow}
  """
  @spec setup_flow(%{cpnet: atom() | ColouredPetriNet.t()}) :: [flow: Schemas.Flow.t()]
  def setup_flow(%{cpnet: cpnet})
      when is_atom(cpnet)
      when is_struct(cpnet, ColouredPetriNet) do
    flow = :flow |> build() |> flow_with_cpnet(cpnet) |> insert()

    [flow: flow]
  end

  @doc """
  Setup an enactment schema for testing.

  ## Parameters

    * `flow` - the flow struct to setup.
    * `initial_markings` - the initial markings to setup.

  ## Returns

      * `enactment` - the enactment struct.

  ## Examples

      setup :setup_flow
      setup :setup_enactment

      @tag cpnet: :simple_sequence
      @tag initial_markings: []
      test "message", %{enactment: enactment}
  """
  @spec setup_enactment(%{flow: Schemas.Flow.t(), initial_markings: list(Marking.t())}) ::
          [enactment: Schemas.Enactment.t()]
  def setup_enactment(%{flow: flow, initial_markings: initial_markings})
      when is_struct(flow, Schemas.Flow) and
             is_list(initial_markings) do
    enactment =
      :enactment
      |> build(flow: flow)
      |> enactment_with_initial_markings(initial_markings)
      |> insert()

    [enactment: enactment]
  end

  @doc """
  Start an enactment schema for testing.

  ## Parameters

    * `enactment` - the enactment struct to start.

  ## Returns

      * `enactment_server` - the PID of the enactment server.

  ## Examples

      setup :setup_flow
      setup :setup_enactment
      setup :start_enactment

      @tag cpnet: :simple_sequence
      @tag initial_markings: []
      test "message", %{enactment_server: enactment_server}
  """
  @spec start_enactment(%{enactment: Schemas.Enactment.t()}) ::
          [enactment_server: GenServer.server()]
  def start_enactment(%{enactment: enactment}) do
    pid = start_link_supervised!({Enactment, enactment_id: enactment.id}, id: enactment.id)

    [enactment_server: pid]
  end

  ## State helpers

  @spec get_enactment_state(GenServer.server()) :: Enactment.t()
  def get_enactment_state(enactment_server) do
    :sys.get_state(enactment_server)
  end

  @doc """
  Get the enactment markings ordered by place name.
  """
  @spec get_enactment_markings(Enactment.t()) :: Enumerable.t(Marking.t())
  def get_enactment_markings(enactment_server) do
    enactment_server
    |> get_enactment_state()
    |> Map.fetch!(:markings)
    |> Map.values()
    |> Enum.sort_by(& &1.place)
  end

  @doc """
  Get the live workitems of the enactment ordered by state and transition name.
  """
  @spec get_enactment_workitems(Enactment.t()) :: [Enactment.Workitem.t()]
  def get_enactment_workitems(enactment_server) do
    enactment_server
    |> get_enactment_state()
    |> Map.fetch!(:workitems)
    |> Map.values()
    |> Enum.sort_by(fn %Enactment.Workitem{} = workitem ->
      {
        Enum.find_index(Enactment.Workitem.__states__(), &(workitem.state === &1)),
        workitem.binding_element.transition,
        workitem.binding_element.binding
      }
    end)
  end

  ## Workitem helpers

  @spec start_workitem(Enactment.Workitem.t(:enabled), GenServer.server()) ::
          Enactment.Workitem.t(:started)
  def start_workitem(%Enactment.Workitem{state: :enabled} = workitem, server) do
    {:ok, [%Enactment.Workitem{state: :started} = workitem]} =
      GenServer.call(server, {:start_workitems, [workitem.id]})

    workitem
  end

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec wait_enactment_to_stop!(GenServer.server(), term()) :: :ok
  def wait_enactment_to_stop!(enactment_server, reason \\ :normal) do
    ref = Process.monitor(enactment_server)

    receive do
      {:DOWN, ^ref, :process, ^enactment_server, ^reason} -> :ok
      # when the enactment server was stopped early
      {:DOWN, ^ref, :process, ^enactment_server, :noproc} -> :ok
    after
      500 ->
        ExUnit.Assertions.flunk("Enactment server is expected to stop, but it's still running")
    end
  end
end
