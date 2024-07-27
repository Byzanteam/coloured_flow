defmodule ColouredFlow.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/Byzanteam/coloured_flow"

  def project do
    [
      app: :coloured_flow,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      # Docs
      name: "ColouredFlow",
      source_url: @repo_url,
      homepage_url: @repo_url,
      docs: docs(),
      package: package()
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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
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

  defp docs do
    [
      main: "ColouredFlow",
      source_url: @repo_url,
      source_ref: "v#{@version}",
      extras: ["README.md"],
      nest_modules_by_prefix: [
        ColouredFlow.Definition,
        ColouredFlow.Enactment,
        ColouredFlow.Notation,
        ColouredFlow.Expression
      ]
    ]
  end

  defp package do
    [
      name: "coloured_flow",
      description: "A workflow based on coloured petri net",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @repo_url
      }
    ]
  end
end
