defmodule ColouredFlow.Validators.Definition.FunctionsValidator do
  @moduledoc """
  This validator ensures that procedures (a.k.a. functions) within a ColouredFlow
  definition are valid.

  It validates these aspects of a procedure:

  1. Procedure names are unique within the net.
  2. The `result` descr of each procedure is fully resolved: every leaf terminates
     at a primitive type, or at a colour set declared in `cpnet.colour_sets`. No
     leaf may reference an unresolved user-defined name.
  """

  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Procedure
  alias ColouredFlow.Validators.Exceptions.MissingColourSetError
  alias ColouredFlow.Validators.Exceptions.UniqueNameViolationError

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()}
          | {:error, UniqueNameViolationError.t() | MissingColourSetError.t()}
  def validate(%ColouredPetriNet{functions: []} = cpnet), do: {:ok, cpnet}

  def validate(%ColouredPetriNet{} = cpnet) do
    declared_colour_sets = MapSet.new(cpnet.colour_sets, & &1.name)

    with :ok <- validate_unique_names(cpnet.functions),
         :ok <- validate_results_resolved(cpnet.functions, declared_colour_sets) do
      {:ok, cpnet}
    end
  end

  @spec validate_unique_names([Procedure.t()]) ::
          :ok | {:error, UniqueNameViolationError.t()}
  defp validate_unique_names(functions) do
    functions
    |> Enum.reduce_while(MapSet.new(), fn %Procedure{name: name}, seen ->
      if MapSet.member?(seen, name) do
        {:halt, {:error, UniqueNameViolationError.exception(scope: :function, name: name)}}
      else
        {:cont, MapSet.put(seen, name)}
      end
    end)
    |> case do
      {:error, _exception} = error -> error
      _seen -> :ok
    end
  end

  @spec validate_results_resolved([Procedure.t()], MapSet.t(ColourSet.name())) ::
          :ok | {:error, MissingColourSetError.t()}
  defp validate_results_resolved(functions, declared_colour_sets) do
    Enum.reduce_while(functions, :ok, fn %Procedure{} = procedure, :ok ->
      case find_unresolved_descr(procedure.result, declared_colour_sets) do
        nil ->
          {:cont, :ok}

        unresolved_name ->
          {:halt, {:error, missing_colour_set_error(procedure, unresolved_name)}}
      end
    end)
  end

  @spec find_unresolved_descr(ColourSet.descr(), MapSet.t(ColourSet.name())) ::
          ColourSet.name() | nil
  defp find_unresolved_descr(descr, declared)

  defp find_unresolved_descr({:integer, []}, _declared), do: nil
  defp find_unresolved_descr({:float, []}, _declared), do: nil
  defp find_unresolved_descr({:boolean, []}, _declared), do: nil
  defp find_unresolved_descr({:binary, []}, _declared), do: nil
  defp find_unresolved_descr({:unit, []}, _declared), do: nil

  defp find_unresolved_descr({:tuple, types}, declared) when is_list(types) do
    Enum.find_value(types, &find_unresolved_descr(&1, declared))
  end

  defp find_unresolved_descr({:map, types}, declared) when is_map(types) do
    Enum.find_value(types, fn {_key, descr} -> find_unresolved_descr(descr, declared) end)
  end

  defp find_unresolved_descr({:enum, items}, _declared) when is_list(items), do: nil

  defp find_unresolved_descr({:union, types}, declared) when is_map(types) do
    Enum.find_value(types, fn {_tag, descr} -> find_unresolved_descr(descr, declared) end)
  end

  defp find_unresolved_descr({:list, type}, declared), do: find_unresolved_descr(type, declared)

  defp find_unresolved_descr({name, []}, declared) when is_atom(name) do
    if MapSet.member?(declared, name), do: nil, else: name
  end

  @spec missing_colour_set_error(Procedure.t(), ColourSet.name()) :: MissingColourSetError.t()
  defp missing_colour_set_error(%Procedure{} = procedure, unresolved_name) do
    MissingColourSetError.exception(
      colour_set: unresolved_name,
      message: """
      procedure #{inspect(procedure.name)} declares a result that references the unknown colour set #{inspect(unresolved_name)}
      """
    )
  end
end
