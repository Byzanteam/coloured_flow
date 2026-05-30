defmodule ColouredFlowDashboard.ColourSetSummary do
  @moduledoc """
  Walks a cpnet's `colour_sets` list and emits one
  `ColouredFlowDashboardWeb.Views.ColourSetDef` per entry — the wire shape the
  SPA's colour-sets panel renders on the enactment and flow detail pages.

  Centralised here so both `FlowCatalogStore.build_detail/2` and
  `EnactmentDetailStore.build_diagram/5` produce byte-identical payloads from
  the same cpnet, keeping the SPA stub simple (one code path).

  `type_summary` is a deterministic Elixir-source-shaped rendering of the
  colour set's `descr` (see `ColouredFlow.Definition.ColourSet.descr/0`) so
  operators see the *shape* of each token type, not just the bare name on the
  place node.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlowDashboardWeb.Views.ColourSetDef

  @doc """
  Serialise the cpnet's colour sets in declaration order.
  """
  @spec build(list(ColourSet.t())) :: list(ColourSetDef.t())
  def build(colour_sets) when is_list(colour_sets) do
    Enum.map(colour_sets, fn %ColourSet{name: name, type: type} ->
      %ColourSetDef{
        name: Atom.to_string(name),
        type_summary: describe(type),
        description: nil
      }
    end)
  end

  @doc """
  Render a single `descr` as an Elixir-source-shaped summary.

  Public so a test (and the future hover tooltip on a place node) can reuse
  the exact same formatting.
  """
  @spec describe(ColourSet.descr()) :: String.t()
  def describe(descr), do: do_describe(descr)

  defp do_describe({:unit, []}), do: "{}"

  defp do_describe({:tuple, members}) do
    "{" <> Enum.map_join(members, ", ", &do_describe/1) <> "}"
  end

  defp do_describe({:map, fields}) do
    body =
      fields
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join(", ", fn {key, value} ->
        Atom.to_string(key) <> ": " <> do_describe(value)
      end)

    "%{" <> body <> "}"
  end

  defp do_describe({:enum, atoms}) do
    Enum.map_join(atoms, " | ", &inspect/1)
  end

  defp do_describe({:union, tagged}) do
    tagged
    |> Enum.sort_by(fn {tag, _descr} -> tag end)
    |> Enum.map_join(" | ", fn {tag, descr} ->
      "{" <> inspect(tag) <> ", " <> do_describe(descr) <> "}"
    end)
  end

  defp do_describe({:list, inner}) do
    "list(" <> do_describe(inner) <> ")"
  end

  defp do_describe({name, []}) when is_atom(name) do
    Atom.to_string(name) <> "()"
  end
end
