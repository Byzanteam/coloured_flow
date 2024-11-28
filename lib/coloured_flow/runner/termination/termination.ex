defmodule ColouredFlow.Runner.Termination do
  @moduledoc """
  Termination criteria evaluation for the enactment.
  """

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.TerminationCriteria.Markings
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Expression.InvalidResult

  @typep markings_binding() :: %{Place.name() => Marking.tokens()}

  @doc """
  Evaluates the termination criteria for the enactment with the given markings.
  Exceptions will be returned if the expression is invalid or the evaluation fails,
  otherwise, the boolean result will indicate whether the enactment should terminate
  based on the criteria.
  """
  @spec should_terminate(markings_criteria :: Markings.t(), markings :: markings_binding()) ::
          {:error, [Exception.t()]} | {:ok, boolean()}
  def should_terminate(markings_criteria, markings)

  def should_terminate(%Markings{expression: nil}, _markings),
    do: {:ok, false}

  def should_terminate(%Markings{} = markings_criteria, markings) when is_map(markings) do
    binding = [markings: markings]

    case ColouredFlow.Expression.eval(markings_criteria.expression.expr, binding, make_env()) do
      {:ok, result} when is_boolean(result) ->
        {:ok, result}

      {:ok, other} ->
        exception =
          InvalidResult.exception(
            expression: markings_criteria.expression,
            message: "The expression should return a boolean value, but got: #{inspect(other)}"
          )

        {:error, [exception]}

      {:error, exceptions} when is_list(exceptions) ->
        {:error, exceptions}
    end
  end

  defp make_env do
    import ColouredFlow.MultiSet, only: [multi_set_coefficient: 2, sigil_MS: 2], warn: false

    __ENV__
  end

  types = ~w[implicit explicit force]a
  @type type() :: unquote(ColouredFlow.Types.make_sum_type(types))

  @spec __types__() :: [type()]
  def __types__, do: unquote(types)
end
