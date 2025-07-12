defmodule ColouredFlow.Definition.TerminationCriteria.Markings do
  @moduledoc """
  The termination criteria applied to place markings. If the criteria are
  satisfied, the corresponding enactment will be terminated, and the reason will
  be `explicit`.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Expression

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    # NOTE (fahchen): Should we put `markings` into a context, like `Termination`?
    # Then, we retrieve the markings by `var!(markings, Termination)`.
    # We can use this to prevent conflicting variables from different contexts.

    field :expression, Expression.t(),
      doc: """
      The expression used to evaluate the criteria. It should return a boolean value.
      If `nil` is given, it will always return `false`.

      ## Binding:

      The expression should only use the `:markings` variable and constants.
      If the constants include a `:markings` constant, it will be overwritten
      by the `markings` variable.

      The `:markings` variable is a map with the place name as the key and
      the marking as the value. It follows the format `%{Place.name() => Marking.tokens()}`.

      ## Examples:

      The enactment will be terminated if the `output` place has more than 1 token:

      ```elixir
      unit = {}

      match?(%{"output" => output_ms} when multi_set_coefficient(output_ms, unit) > 0, markings)
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
