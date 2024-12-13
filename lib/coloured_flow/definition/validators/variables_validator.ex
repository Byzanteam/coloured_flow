defmodule ColouredFlow.Definition.Validators.VariablesValidator do
  @moduledoc """
  The variables validator ensures that the variables in a ColouredFlow definition are valid.

  A variable is valid if its colour_set is valid.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Validators.Exceptions.MissingColourSetError
  alias ColouredFlow.Definition.Variable

  @spec validate(variables, ColouredPetriNet.t()) ::
          {:ok, variables} | {:error, MissingColourSetError.t()}
        when variables: [Variable.t()]
  def validate([], %ColouredPetriNet{}), do: {:ok, []}

  def validate(variables, %ColouredPetriNet{} = cpent) when is_list(variables) do
    colour_sets = MapSet.new(cpent.colour_sets, & &1.name)

    variables
    |> Enum.find(fn %Variable{} = variable ->
      not MapSet.member?(colour_sets, variable.colour_set)
    end)
    |> case do
      nil ->
        {:ok, variables}

      %Variable{} = variable ->
        {
          :error,
          MissingColourSetError.exception(
            colour_set: variable.colour_set,
            message: """
            variable: #{inspect(variable)}
            """
          )
        }
    end
  end
end
