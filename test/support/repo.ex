defmodule ColouredFlow.TestRepo do
  use Ecto.Repo,
    otp_app: :coloured_flow,
    adapter: Ecto.Adapters.Postgres

  @spec migrate() :: :ok
  def migrate do
    Ecto.Migrator.run(
      __MODULE__,
      [{0, ColouredFlow.Runner.Migrations.V0}],
      :up,
      all: true
    )

    :ok
  end
end
