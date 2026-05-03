defmodule ColouredFlow.Runner.Migrations.V4 do
  @moduledoc """
  Adds a unique index on `flows.name` so `Storage.Default.setup_flow!/2` can
  safely upsert under racing callers — Postgres rejects the second insert with a
  unique violation, which the storage retries via `Repo.get_by/2`.
  """

  use Ecto.Migration

  @prefix "coloured_flow"

  @spec change(prefix: String.t()) :: :ok
  def change(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @prefix)

    create unique_index("flows", [:name], prefix: prefix, name: :flows_name_index)

    :ok
  end
end
