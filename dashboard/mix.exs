defmodule ColouredFlowDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :coloured_flow_dashboard,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:musubi_ts],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {ColouredFlowDashboard.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:coloured_flow, path: ".."},
      {:musubi, "~> 0.7.1"},
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "deps.unlock --check-unused",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "compile.musubi_ts --check",
        "dialyzer",
        # Re-shell into `mix test` so MIX_ENV=test is honoured even when the
        # alias chain runs from `:dev` (so dialyzer's PLT scan doesn't pick
        # up `test/support/` and trip on ExUnit shims).
        "cmd env MIX_ENV=test mix test"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts/coloured_flow_dashboard.plt",
      plt_core_path: "priv/plts/core.plt",
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end
end
