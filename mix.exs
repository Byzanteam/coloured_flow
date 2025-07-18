defmodule ColouredFlow.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/Byzanteam/coloured_flow"

  def project do
    [
      app: :coloured_flow,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: test_coverage(),
      dprint_markdown_formatter: [
        format_module_attributes: true
      ],
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
      {:dprint_markdown_formatter, "~> 0.3.0", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.12"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:ex_machina, "~> 2.8.0", only: :test},
      {:jason, "~> 1.0"},
      {:jet_credo, [github: "Byzanteam/jet_credo", only: [:dev, :test], runtime: false]},
      {:kino, "~> 0.14.1", only: [:dev, :test]},
      {:postgrex, ">= 0.0.0"},
      {:telemetry, "~> 1.0"},
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

  defp test_coverage do
    [
      ignore_modules: [
        ColouredFlow.Runner.Enactment.Registry,
        ColouredFlow.Runner.Storage.Schemas.Types,
        ColouredFlow.Runner.Supervisor,
        Inspect.ColouredFlow.Expression.Scope,
        TypedStructor.Plugins.DocFields,
        ~r/ColouredFlow.Runner.Migrations.*/
      ]
    ]
  end

  defp docs do
    [
      main: "ColouredFlow",
      source_url: @repo_url,
      source_ref: "v#{@version}",
      extras: ["README.md"],
      nest_modules_by_prefix: [
        ColouredFlow.Builder,
        ColouredFlow.Definition,
        ColouredFlow.EnabledBindingElements,
        ColouredFlow.Enactment,
        ColouredFlow.Expression,
        ColouredFlow.Notation,
        ColouredFlow.Runner,
        ColouredFlow.Runner.Enactment,
        ColouredFlow.Runner.Storage,
        ColouredFlow.Validators
      ],
      groups_for_docs: [
        enactment: &(&1[:group] == :enactment),
        snapshot: &(&1[:group] == :snapshot),
        workitem: &(&1[:group] == :workitem)
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
      end,
      formatters: ["html"]
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
