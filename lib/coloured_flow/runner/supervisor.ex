defmodule ColouredFlow.Runner.Supervisor do
  @moduledoc """
  The supervisor of the coloured_flow runner.

  ## Runner Supervision Tree
  ```mermaid
  flowchart TB
      S["Supervisor"]
      S --> DS["Definition Storage"]
      S --> EDS["Enactment (Dyn) Supervisor"]
      EDS --> E1["Enactment (1)"]
      EDS --> EN["Enactment (N)"]
  ```
  """

  use Supervisor

  # credo:disable-for-next-line JetCredo.Checks.ExplicitAnyType
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    children = [
      ColouredFlow.Runner.Enactment.Registry,
      ColouredFlow.Runner.Enactment.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
