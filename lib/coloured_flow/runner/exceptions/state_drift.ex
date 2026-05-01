defmodule ColouredFlow.Runner.Exceptions.StateDrift do
  @moduledoc """
  Raised inside an enactment when its in-memory state diverged from storage.

  Common causes:

  - `unexpected_updated_rows` from `Storage.Default.transition_workitems/2` — the
    workitem the GenServer believed was live no longer matches the database row.
  - `Repo.transaction/1` rollback during `produce_workitems` /
    `complete_workitems` / `terminate_enactment` — the persistence layer was
    unable to apply the change atomically.

  Surfaced as a Tier 2 enactment-fatal error.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :operation, atom()
    field :context, map(), default: %{}
    field :error_code, atom(), default: :state_drift
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Enactment #{exception.enactment_id} state drifted from storage during `#{exception.operation}`.
    Context: #{inspect(exception.context)}
    """
  end
end
