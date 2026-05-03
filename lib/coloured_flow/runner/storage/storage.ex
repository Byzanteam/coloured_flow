defmodule ColouredFlow.Runner.Storage do
  @moduledoc """
  The Storage is responsible for storing the data that is being produced by the
  Runner.

  To use `ColouredFlow.Runner.Storage.Default`, you need to configure the storage
  module in your config.exs:

  ```elixir
  config :coloured_flow, ColouredFlow.Runner.Storage,
    repo: ColouredFlow.TestRepo,
    storage: ColouredFlow.Runner.Storage.Default
  ```
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Enactment.Occurrence

  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Exceptions
  alias ColouredFlow.Runner.Storage.Schemas

  @type enactment_id() :: Ecto.UUID.t()
  @type flow_id() :: Ecto.UUID.t()

  @doc """
  Get the flow of an enactment.
  """
  @callback get_flow_by_enactment(enactment_id()) :: ColouredPetriNet.t()

  @doc """
  Returns the initial markings for the given enactment.
  """
  @doc group: :enactment
  @callback get_initial_markings(enactment_id()) :: [Marking.t()]

  @doc """
  Returns a stream of occurrences for the given enactment, that occurred after the
  given `from`(exclusive) position.
  """
  @doc group: :enactment
  @callback occurrences_stream(enactment_id(), from :: non_neg_integer()) ::
              Enumerable.t(Occurrence.t())

  @doc """
  Records an exceptional event in `enactment_logs`. The row is written with
  `kind = :exception`; `enactments.state` is **not** changed by this call.

  The state column flips to `:exception` only when `ensure_runnable/1` trips the
  consecutive-exception circuit breaker.
  """
  @doc group: :enactment
  @callback exception_occurs(
              enactment_id(),
              reason :: ColouredFlow.Runner.Exception.reason(),
              exception :: Exception.t()
            ) :: :ok

  @doc """
  Confirms that the enactment is allowed to start. Called from `init/1` (via
  `handle_continue/2`) before any state is loaded.

  Returns `:ok` when the enactment is healthy. Returns `{:error, reason}` when the
  runner should abort startup:

  | reason                      | meaning                                                                               |
  | --------------------------- | ------------------------------------------------------------------------------------- |
  | `:terminated`               | The enactment has already terminated.                                                 |
  | `:already_in_exception`     | The enactment is already in `:exception` state and must be retried first.             |
  | `:crash_threshold_exceeded` | The most recent three log rows are all exceptions; state was flipped to `:exception`. |
  """
  @doc group: :enactment
  @callback ensure_runnable(enactment_id()) ::
              :ok | {:error, :terminated | :already_in_exception | :crash_threshold_exceeded}

  @doc """
  Idempotent flow upsert keyed by `name`.

  Returns the existing flow when one with the same name is already stored,
  otherwise inserts a fresh row using the supplied definition. The shape of the
  returned value is storage-specific (an Ecto schema for `Storage.Default`, an
  Erlang record for `Storage.InMemory`). Callers needing only the id should
  pattern-match accordingly.
  """
  @doc group: :flow
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback setup_flow!(name :: String.t(), ColouredPetriNet.t()) :: term()

  @doc """
  Insert an enactment.
  """
  @doc group: :enactment
  @callback insert_enactment(params :: map()) :: {:ok, Schemas.Enactment.t()}

  @doc """
  Convenience for inserting an enactment from a flow handle (whatever
  `setup_flow!/2` returned) plus an initial-markings list. The shape of the
  returned value is storage-specific.
  """
  @doc group: :enactment
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @callback insert_enactment!(flow :: term(), [Marking.t()]) :: term()

  @doc """
  The enactment is terminated, and the corresponding enactment will be stopped.
  There are three types of termination:

  | Type        | Description                                                        |
  | ----------- | ------------------------------------------------------------------ |
  | `:implicit` | If there are no more enabled workitems currently or in the future. |
  | `:explicit` | When the user-defined termination criteria are met.                |
  | `:force`    | The enactment is terminated forcibly by the user.                  |
  """
  @doc group: :enactment
  @callback terminate_enactment(
              enactment_id(),
              type :: :implicit | :explicit | :force,
              final_markings :: [Marking.t()],
              options :: [message: String.t()]
            ) :: :ok

  @doc """
  Reoffers an enactment that landed in `:exception` state. Writes a `:retried` log
  row and flips `enactments.state` back to `:running`.
  """
  @doc group: :enactment
  @callback retry_enactment(enactment_id(), options :: [message: String.t()]) :: :ok

  @doc """
  Returns a list of live workitems for the given enactment.
  """
  @doc group: :workitem
  @callback list_live_workitems(enactment_id()) :: [Workitem.t(Workitem.live_state())]

  @type transition_option() :: {:action, Workitem.transition_action()}

  @doc """
  Produces the workitems for the given enactment.
  """
  @doc group: :workitem
  @callback produce_workitems(
              enactment_id(),
              binding_elements :: Enumerable.t(BindingElement.t())
            ) :: [Workitem.t(:enabled)]

  @doc group: :workitem
  @callback start_workitems(
              started_workitems :: [Workitem.t(:started)],
              options :: [transition_option()]
            ) :: :ok

  @doc group: :workitem
  @callback withdraw_workitems(
              withdrawn_workitems :: [Workitem.t(:withdrawn)],
              options :: [transition_option()]
            ) :: :ok

  @doc group: :workitem
  @callback complete_workitems(
              enactment_id(),
              current_version :: non_neg_integer(),
              workitem_occurrences :: [{Workitem.t(:completed), Occurrence.t()}],
              options :: [transition_option()]
            ) :: :ok

  @doc """
  Takes a snapshot of the given enactment.
  """
  @doc group: :snapshot
  @callback take_enactment_snapshot(enactment_id(), snapshot :: Snapshot.t()) :: :ok

  @doc """
  Reads the snapshot of the given enactment.

  Returns `{:error, %Exceptions.SnapshotCorrupt{}}` when the snapshot row exists
  but cannot be decoded. Callers self-heal by recording the exception via
  `exception_occurs/3` and replaying from initial markings; the next
  `take_enactment_snapshot/2` overwrites the bad row.
  """
  @doc group: :snapshot
  @callback read_enactment_snapshot(enactment_id()) ::
              {:ok, Snapshot.t()}
              | :error
              | {:error, Exceptions.SnapshotCorrupt.t()}

  @doc false
  @spec get_flow_by_enactment(enactment_id()) :: ColouredPetriNet.t()
  def get_flow_by_enactment(enactment_id) do
    __storage__().get_flow_by_enactment(enactment_id)
  end

  @doc false
  @spec get_initial_markings(enactment_id()) :: [Marking.t()]
  def get_initial_markings(enactment_id) do
    __storage__().get_initial_markings(enactment_id)
  end

  @doc false
  @spec occurrences_stream(enactment_id(), from :: non_neg_integer()) ::
          Enumerable.t(Occurrence.t())
  def occurrences_stream(enactment_id, from) do
    __storage__().occurrences_stream(enactment_id, from)
  end

  @doc false
  @spec exception_occurs(
          enactment_id(),
          ColouredFlow.Runner.Exception.reason(),
          Exception.t()
        ) :: :ok
  def exception_occurs(enactment_id, reason, exception) do
    __storage__().exception_occurs(enactment_id, reason, exception)
  end

  @doc false
  @spec ensure_runnable(enactment_id()) ::
          :ok | {:error, :terminated | :already_in_exception | :crash_threshold_exceeded}
  def ensure_runnable(enactment_id) do
    __storage__().ensure_runnable(enactment_id)
  end

  @doc false
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec setup_flow!(name :: String.t(), ColouredPetriNet.t()) :: term()
  def setup_flow!(name, %ColouredPetriNet{} = definition) when is_binary(name) do
    __storage__().setup_flow!(name, definition)
  end

  @doc false
  @spec insert_enactment(params :: map()) :: {:ok, Schemas.Enactment.t()}
  def insert_enactment(params) do
    __storage__().insert_enactment(params)
  end

  @doc false
  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec insert_enactment!(flow :: term(), [Marking.t()]) :: term()
  def insert_enactment!(flow, initial_markings) when is_list(initial_markings) do
    __storage__().insert_enactment!(flow, initial_markings)
  end

  @doc false
  @spec terminate_enactment(
          enactment_id(),
          type :: ColouredFlow.Runner.Termination.type(),
          final_markings :: [Marking.t()],
          options :: [message: String.t()]
        ) :: :ok
  def terminate_enactment(enactment_id, type, final_markings, options) do
    __storage__().terminate_enactment(enactment_id, type, final_markings, options)
  end

  @doc false
  @spec retry_enactment(enactment_id(), options :: [message: String.t()]) :: :ok
  def retry_enactment(enactment_id, options) do
    __storage__().retry_enactment(enactment_id, options)
  end

  @doc false
  @spec list_live_workitems(enactment_id()) :: [Workitem.t(Workitem.live_state())]
  def list_live_workitems(enactment_id) do
    __storage__().list_live_workitems(enactment_id)
  end

  @doc false
  @spec produce_workitems(enactment_id(), Enumerable.t(BindingElement.t())) ::
          [Workitem.t(:enabled)]
  def produce_workitems(enactment_id, binding_elements) do
    __storage__().produce_workitems(enactment_id, binding_elements)
  end

  @doc false
  @spec start_workitems([Workitem.t(:started)], [transition_option()]) :: :ok
  def start_workitems(workitems, options) do
    __storage__().start_workitems(workitems, options)
  end

  @doc false
  @spec withdraw_workitems([Workitem.t(:withdrawn)], [transition_option()]) :: :ok
  def withdraw_workitems(workitems, options) do
    __storage__().withdraw_workitems(workitems, options)
  end

  @doc false
  @spec complete_workitems(
          enactment_id(),
          current_version :: non_neg_integer(),
          workitem_occurrences :: [{Workitem.t(:completed), Occurrence.t()}],
          [transition_option()]
        ) :: :ok
  def complete_workitems(enactment_id, current_version, workitem_occurrences, options) do
    __storage__().complete_workitems(enactment_id, current_version, workitem_occurrences, options)
  end

  @doc false
  @spec take_enactment_snapshot(enactment_id(), Snapshot.t()) :: :ok
  def take_enactment_snapshot(enactment_id, snapshot) do
    __storage__().take_enactment_snapshot(enactment_id, snapshot)
  end

  @doc false
  @spec read_enactment_snapshot(enactment_id()) ::
          {:ok, Snapshot.t()}
          | :error
          | {:error, Exceptions.SnapshotCorrupt.t()}
  def read_enactment_snapshot(enactment_id) do
    __storage__().read_enactment_snapshot(enactment_id)
  end

  @doc """
  Returns the storage module.
  """
  @spec __storage__() :: module()
  def __storage__ do
    Application.fetch_env!(:coloured_flow, ColouredFlow.Runner.Storage)[:storage]
  end
end
