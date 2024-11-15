defmodule ColouredFlow.Definition.TerminationCriteria.Markings do
  @moduledoc """
  The termination criteria applied to place markings. If the criteria are satisfied,
  the corresponding enactment will be terminated, and the reason will be `explicit`.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Expression

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    field :expression, Expression.t(),
      doc: """
      The expression used to evaluate the criteria. It should return a boolean value.
      If `nil` is given, it will always return `false`.

      ## Examples:

      The enactment will be terminated if the `output` place has more than 1 token:

      ```elixir
      unit = {}

      match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, unit), markings)
      ```

      The enactment will be terminated:
      1. if the `first` place has more than 3 tokens of `"foo"`,
      2. or the `second` place has more than 2 tokens of `2`.

      ```elixir
      case markings do
        %{"first" => ms} when multi_set_coefficient(ms, "foo") > 3 ->
          true

        %{"second" => ms} when multi_set_coefficient(ms, 2) > 2 ->
          true

        _markings ->
          false
      end
      ```
      """
  end
end
