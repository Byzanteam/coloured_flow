defmodule ColouredFlow.Runner.Exceptions.RestartLoop do
  @moduledoc """
  The enactment GenServer crashed enough consecutive times that
  `Storage.crash_threshold_exceeded?/1` reports true. `init/1` aborts via
  `:ignore` to prevent the supervisor from restarting in a tight loop, and the
  enactment row is flipped to `:exception` so operators can reoffer once the
  underlying cause is fixed.
  """

  use TypedStructor

  alias ColouredFlow.Runner.Storage

  typed_structor definer: :defexception, enforce: true do
    field :enactment_id, Storage.enactment_id()
  end

  @impl Exception
  def exception(arguments) do
    struct!(__MODULE__, arguments)
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "Enactment #{inspect(exception.enactment_id)} exceeded the crash threshold. " <>
      "Aborting init to break the restart loop."
  end
end
