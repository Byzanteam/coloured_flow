defmodule ColouredFlow.Validators.Definition.ConstantsValidator do
  @moduledoc """
  This validator ensures that constants within a ColouredFlow definition are valid.

  It validates these aspects of a constant:
  1. The colour_set should be defined in the ColouredPetriNet.
  2. The value should be of a type that matches the colour_set.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColourSet.ColourSetMismatch
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Constant

  @spec validate(constants, ColouredPetriNet.t()) ::
          {:ok, constants} | {:error, ColourSetMismatch.t()}
        when constants: [Constant.t()]
  def validate([], %ColouredPetriNet{}), do: {:ok, []}

  def validate(constants, %ColouredPetriNet{} = cpnet) when is_list(constants) do
    context = build_of_type_context(cpnet)

    constants
    |> Enum.find(fn %Constant{} = constant ->
      match?(
        :error,
        ColourSet.Of.of_type(
          constant.value,
          ColourSet.Descr.type(constant.colour_set),
          context
        )
      )
    end)
    |> case do
      nil ->
        {:ok, constants}

      %Constant{} = constant ->
        {
          :error,
          ColourSetMismatch.exception(colour_set: constant.colour_set, value: constant.value)
        }
    end
  end

  defp build_of_type_context(%ColouredPetriNet{} = cpnet) do
    types =
      Map.new(cpnet.colour_sets, fn %ColourSet{name: name, type: type} ->
        {name, type}
      end)

    %{fetch_type: &Map.fetch(types, &1)}
  end
end
