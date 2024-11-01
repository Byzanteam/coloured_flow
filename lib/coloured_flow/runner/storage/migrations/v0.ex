defmodule ColouredFlow.Runner.Migrations.V0 do
  @moduledoc false

  use Ecto.Migration

  @prefix "coloured_flow"

  @table_options [
    primary_key: false
  ]

  @timestamps_opts [type: :naive_datetime_usec]

  @spec change(prefix: String.t()) :: :ok
  def change(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @prefix)
    table_options = Keyword.put(@table_options, :prefix, prefix)

    execute "CREATE SCHEMA IF NOT EXISTS #{prefix}",
            "DROP SCHEMA IF EXISTS #{prefix} CASCADE"

    create table("flows", table_options) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :version, :integer, null: false
      add :data, :jsonb, null: false

      timestamps([{:updated_at, false} | @timestamps_opts])
    end

    create unique_index("flows", [:name, :version], prefix: prefix)

    create table("enactments", table_options) do
      add :id, :binary_id, primary_key: true
      add :flow_id, references("flows", type: :binary_id, on_delete: :delete_all), null: false
      add :data, :jsonb, null: false

      timestamps(@timestamps_opts)
    end

    create table("workitems", table_options) do
      add :id, :binary_id, primary_key: true

      add :enactment_id, references("enactments", type: :binary_id, on_delete: :delete_all),
        null: false

      add :state, :string, null: false
      add :data, :jsonb, null: false

      timestamps(@timestamps_opts)
    end

    create table("occurrences", table_options) do
      add :enactment_id, references("enactments", type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :step_number, :integer, null: false, primary_key: true

      # We don’t expect to delete work items that have already occurred
      add :workitem_id, references("workitems", type: :binary_id, on_delete: :nothing),
        null: false

      add :data, :jsonb, null: false

      timestamps([{:updated_at, false} | @timestamps_opts])
    end

    create table("snapshots", table_options) do
      add :enactment_id, references("enactments", type: :binary_id, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :version, :integer, null: false
      add :data, :jsonb, null: false

      timestamps(@timestamps_opts)
    end

    :ok
  end
end
