defmodule ColouredFlowDashboard.DataCase do
  @moduledoc """
  Test case template for tests that touch the application's data layer.

  Wraps each test in an Ecto SQL sandbox so changes are rolled back. Pass
  `use ColouredFlowDashboard.DataCase, async: true` for concurrent suites.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias ColouredFlowDashboard.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ColouredFlowDashboard.DataCase
    end
  end

  setup tags do
    ColouredFlowDashboard.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  @spec setup_sandbox(map()) :: :ok
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(ColouredFlowDashboard.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)
  """
  @spec errors_on(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
