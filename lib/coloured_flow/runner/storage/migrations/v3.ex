defmodule ColouredFlow.Runner.Migrations.V3 do
  @moduledoc false

  use Ecto.Migration

  @prefix "coloured_flow"

  @spec change(prefix: String.t()) :: :ok
  def change(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @prefix)

    rename table("enactment_logs", prefix: prefix), :state, to: :kind

    alter table("enactment_logs", prefix: prefix) do
      add :retry, :jsonb
    end

    # Reclassify rows where the previous `state` column overloaded
    # `:running` for non-fatal exception records (snapshot self-heal,
    # crash markers): those rows already carry an `exception` payload.
    execute(
      "UPDATE #{prefix}.enactment_logs " <>
        "SET kind = 'exception' WHERE kind = 'running' AND exception IS NOT NULL",
      "UPDATE #{prefix}.enactment_logs " <>
        "SET kind = 'running' WHERE kind = 'exception' AND exception IS NOT NULL"
    )

    # The remaining `:running` rows correspond to enactment-start markers and
    # become `:started` under the new schema.
    execute(
      "UPDATE #{prefix}.enactment_logs " <>
        "SET kind = 'started' WHERE kind = 'running' AND exception IS NULL AND termination IS NULL",
      "UPDATE #{prefix}.enactment_logs SET kind = 'running' WHERE kind = 'started'"
    )

    :ok
  end
end
