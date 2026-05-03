defmodule ColouredFlow.DSL.Storage do
  @moduledoc """
  Compile-time-fixed adapter that bridges DSL-generated `setup_flow!/0` and
  `insert_enactment!/{1,2}` helpers to the existing storage primitives.

  The adapter's two functions are dispatched on the storage module supplied to
  `use ColouredFlow.DSL, storage: ...` — there is no behaviour extension on
  `ColouredFlow.Runner.Storage`. Each clause uses only public API of the matching
  storage backend, so swapping backends is a pure configuration change.

  Neither `setup_flow!/3` nor `insert_enactment!/3` is idempotent: every
  invocation creates a fresh row. Callers needing dedup must enforce it at
  application level.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Storage.InMemory
  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas

  @typedoc "Storage-specific flow handle. Pattern-match per backend."
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @type flow_handle() :: term()

  @typedoc "Storage-specific enactment handle. Pattern-match per backend."
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @type enactment_handle() :: term()

  @doc """
  Insert a flow row using the configured storage. Returns the storage's flow
  handle.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec setup_flow!(module(), name :: String.t() | nil, ColouredPetriNet.t()) :: flow_handle()
  def setup_flow!(InMemory, _name, %ColouredPetriNet{} = cpnet) do
    InMemory.insert_flow!(cpnet)
  end

  def setup_flow!(ColouredFlow.Runner.Storage.Default, name, %ColouredPetriNet{} = cpnet) do
    %Schemas.Flow{}
    |> Ecto.Changeset.cast(%{name: name, definition: cpnet}, [:name, :definition])
    |> Repo.insert!([])
  end

  def setup_flow!(other, _name, _cpnet)
      when is_atom(other) and other not in [InMemory, ColouredFlow.Runner.Storage.Default] do
    raise ArgumentError, """
    ColouredFlow.DSL.Storage does not know how to insert flows under #{inspect(other)}.

    Supported storage modules: #{inspect([InMemory, ColouredFlow.Runner.Storage.Default])}.

    Use one of those (via `use ColouredFlow.DSL, storage: ...`) or implement
    insertion at the application layer instead of relying on the DSL helper.
    """
  end

  @doc """
  Insert an enactment for the given flow + initial markings using the configured
  storage. Returns the storage's enactment handle.
  """
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec insert_enactment!(module(), flow_handle(), [Marking.t()]) :: enactment_handle()
  def insert_enactment!(InMemory, flow, initial_markings) when is_list(initial_markings) do
    InMemory.insert_enactment!(flow, initial_markings)
  end

  def insert_enactment!(ColouredFlow.Runner.Storage.Default, %Schemas.Flow{id: flow_id}, markings)
      when is_list(markings) do
    {:ok, enactment} =
      ColouredFlow.Runner.Storage.Default.insert_enactment(%{
        flow_id: flow_id,
        initial_markings: markings
      })

    enactment
  end

  def insert_enactment!(other, _flow, _markings)
      when is_atom(other) and other not in [InMemory, ColouredFlow.Runner.Storage.Default] do
    raise ArgumentError, """
    ColouredFlow.DSL.Storage does not know how to insert enactments under #{inspect(other)}.

    Supported storage modules: #{inspect([InMemory, ColouredFlow.Runner.Storage.Default])}.

    Use one of those (via `use ColouredFlow.DSL, storage: ...`) or implement
    insertion at the application layer instead of relying on the DSL helper.
    """
  end
end
