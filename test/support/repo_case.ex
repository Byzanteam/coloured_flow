defmodule ColouredFlow.RepoCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      alias ColouredFlow.Runner.Storage.Schemas
      alias ColouredFlow.TestRepo, as: Repo

      import ColouredFlow.RepoCase
      import ColouredFlow.Factory
    end
  end

  setup tags do
    alias Ecto.Adapters.SQL.Sandbox

    pid = Sandbox.start_owner!(ColouredFlow.TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
