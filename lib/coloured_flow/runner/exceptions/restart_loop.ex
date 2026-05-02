defmodule ColouredFlow.Runner.Exceptions.RestartLoop do
  @moduledoc """
  The enactment GenServer crashed `count` consecutive times without making any
  progress (no new occurrences). `init/1` aborts via `:ignore` to prevent the
  supervisor from restarting in a tight loop, and the enactment row is flipped to
  `:exception` so operators can reoffer once the underlying cause is fixed.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
    field :count, non_neg_integer()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Enactment #{inspect(exception.enactment_id)} crashed #{exception.count} \
    consecutive times without making progress. Aborting init to break the \
    restart loop.\
    """
  end
end
