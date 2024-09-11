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
      elixirc_paths: elixirc_paths(Mix.env()),
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
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:jason, "~> 1.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:jet_credo, [github: "Byzanteam/jet_credo", only: [:dev, :test], runtime: false]},
      {:typed_structor, "~> 0.4"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
        ColouredFlow.EnabledBindingElements,
        ColouredFlow.Enactment,
        ColouredFlow.Expression,
        ColouredFlow.Notation
      ],
      before_closing_body_tag: fn
        :html ->
          """
          <script>
            function mermaidLoaded() {
              mermaid.initialize({
                startOnLoad: false,
                theme: document.body.className.includes("dark") ? "dark" : "default"
              });
              let id = 0;
              for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
                const preEl = codeEl.parentElement;
                const graphDefinition = codeEl.textContent;
                const graphEl = document.createElement("div");
                const graphId = "mermaid-graph-" + id++;
                mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
                  graphEl.innerHTML = svg;
                  bindFunctions?.(graphEl);
                  preEl.insertAdjacentElement("afterend", graphEl);
                  preEl.remove();
                });
              }
            }
          </script>
          <script async src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js" onload="mermaidLoaded();"></script>
          """

        _ ->
          ""
      end
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
