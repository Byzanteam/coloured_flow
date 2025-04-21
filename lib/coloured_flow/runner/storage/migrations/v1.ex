defmodule ColouredFlow.Runner.Migrations.V1 do
  @moduledoc false

  use Ecto.Migration

  @prefix "coloured_flow"

  @table_options [
    primary_key: false
  ]

  @timestamps_opts [type: :utc_datetime_usec]

  @spec change(prefix: String.t()) :: :ok
  def change(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @prefix)
    table_options = Keyword.put(@table_options, :prefix, prefix)
    index_options = [prefix: prefix]

    create table("workitem_logs", table_options) do
      add :id, :binary_id, primary_key: true

      add :workitem_id, references("workitems", type: :binary_id, on_delete: :delete_all),
        null: false

      add :enactment_id, references("enactments", type: :binary_id, on_delete: :delete_all),
        null: false

      add :from_state, :string, null: false
      add :to_state, :string, null: false
      add :action, :string, null: false

      timestamps([{:updated_at, false} | @timestamps_opts])
    end

    # Index for querying logs by enactment_id, ordered by insertion time
    create index("workitem_logs", [:enactment_id, :inserted_at], index_options)

    :ok
  end
end
