defmodule ColouredFlow.MixProject do
  use Mix.Project

  def project do
    [
      app: :coloured_flow,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:jet_credo, [github: "Byzanteam/jet_credo", only: [:dev, :test], runtime: false]},
      {:typed_structor, "~> 0.4"}
    ]
  end

  defp aliases do
    [
      check: ["format", "deps.unlock --check-unused", "credo --strict", "dialyzer"]
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts/coloured_flow.plt",
      plt_core_path: "priv/plts/core.plt"
    ]
  end
end
