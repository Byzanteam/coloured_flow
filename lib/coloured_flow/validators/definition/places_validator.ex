defmodule ColouredFlow.Validators.Definition.PlacesValidator do
  @moduledoc """
  The places validator ensures that each place in a ColouredFlow definition
  references a declared colour set.
  """

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Validators.Exceptions.MissingColourSetError

  @doc """
  Validate that every `%Place{}` in `cpnet.places` references a colour set present
  in `cpnet.colour_sets`. Returns `{:ok, cpnet}` on success, or
  `{:error, MissingColourSetError.t()}` for the first offending place.
  """
  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, MissingColourSetError.t()}
  def validate(%ColouredPetriNet{} = cpnet) do
    colour_sets = MapSet.new(cpnet.colour_sets, & &1.name)

    cpnet.places
    |> Enum.find(fn %Place{} = place ->
      not MapSet.member?(colour_sets, place.colour_set)
    end)
    |> case do
      nil ->
        {:ok, cpnet}

      %Place{} = place ->
        {
          :error,
          MissingColourSetError.exception(
            colour_set: place.colour_set,
            message: """
            place #{inspect(place.name)} references unknown colour set #{inspect(place.colour_set)}
            """
          )
        }
    end
  end
end
