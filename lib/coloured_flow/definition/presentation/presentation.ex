defmodule ColouredFlow.Definition.Presentation do
  @moduledoc """
  Generate a graph representation of the petri net.
  """

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.Transition

  @new_line "\n"
  @indent "  "

  @doc """
  Generate a [mermaid](https://mermaid.js.org/) representation of the coloured
  petri net.
  """
  @spec to_mermaid(ColouredPetriNet.t()) :: String.t()
  def to_mermaid(%ColouredPetriNet{} = cpnet) do
    colsets = cpnet.colour_sets |> Enum.sort_by(& &1.name) |> Enum.map(&to_mermaid_colour_set/1)
    places = cpnet.places |> Enum.sort_by(& &1.name) |> Enum.map(&to_mermaid_place/1)

    transitions =
      cpnet.transitions |> Enum.sort_by(& &1.name) |> Enum.map(&to_mermaid_transition/1)

    arcs =
      cpnet.arcs
      |> Enum.sort_by(fn %Arc{} = arc -> {arc.place, arc.orientation, arc.transition} end)
      |> Enum.map(&to_mermaid_arc/1)

    line_sep = @new_line <> @indent

    """
    flowchart TB
      #{Enum.join(colsets, line_sep)}

      %% places
      #{Enum.join(places, line_sep)}

      %% transitions
      #{Enum.join(transitions, line_sep)}

      %% arcs
      #{Enum.join(arcs, line_sep)}
    """
  end

  defp to_mermaid_colour_set(%ColourSet{name: name, type: type}) do
    alias ColouredFlow.Definition.ColourSet.Descr

    # `Macro.to_string` may return multi-line output for composite descrs
    # (maps, nested tuples). Mermaid's `%%` only comments a single line, so
    # trailing lines would escape the comment and break the parser. Prefix
    # every continuation line with `%%` so the whole descr stays commented.
    rendered =
      type
      |> Descr.to_quoted()
      |> Macro.to_string()
      |> String.replace("\n", "\n  %% ")

    "%% colset #{compose_call(name)} :: #{rendered}"
  end

  defp to_mermaid_place(%Place{name: name, colour_set: colour_set}) do
    "#{name}((#{name}<br>:#{colour_set}:))"
  end

  defp to_mermaid_transition(%Transition{name: name}) do
    "#{name}[#{name}]"
  end

  defp to_mermaid_arc(%Arc{
         label: label,
         place: place,
         transition: transition,
         orientation: :p_to_t,
         expression: expression
       }) do
    "#{place} -->|#{escape_arc_label(label || expression.code)}| #{transition}"
  end

  defp to_mermaid_arc(%Arc{
         label: label,
         place: place,
         transition: transition,
         orientation: :t_to_p,
         expression: expression
       }) do
    "#{transition} -->|#{escape_arc_label(label || expression.code)}| #{place}"
  end

  # Mermaid's `-->|label|` edge form rejects unbalanced/special chars.
  # The dash form (`--label-->`) is even pickier — `[`, `]`, `{`, `"` all
  # break the parser. Quote the whole label so mermaid treats it as a
  # string literal, and escape embedded quotes.
  defp escape_arc_label(label) do
    "\"" <> String.replace(label, "\"", "#quot;") <> "\""
  end

  @spec compose_call(atom()) :: String.t()
  defp compose_call(name) when is_atom(name) do
    Macro.to_string({name, [], []})
  end
end
