defmodule ColouredFlow.Definition.Validators.ColourSetValidator do
  @moduledoc """
  This validator ensures that colour sets within a ColouredFlow definition are valid.

  It validates these aspects of a colour set:
  - name can be a built-in type
  - types should be valid
  - compound type supported
  - recursive types not supported
  """

  alias ColouredFlow.Definition.ColourSet.Descr
  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Validators.Exceptions.InvalidColourSetError

  @spec validate(ColouredPetriNet.t()) ::
          {:ok, ColouredPetriNet.t()} | {:error, InvalidColourSetError.t()}
  def validate(%ColouredPetriNet{} = cpnet) do
    types = Map.new(cpnet.colour_sets, &{&1.name, &1.type})

    context = %{
      fetch_type: fn name -> Map.fetch(types, name) end,
      validated: MapSet.new(),
      validating: []
    }

    built_in_types = Descr.__built_in_types__()

    types
    |> reduce_while_and_wrap(context, fn {name, descr}, acc ->
      cond do
        name in built_in_types ->
          {:error,
           InvalidColourSetError.exception(
             message:
               "#{inspect(name)} is a built-in type, it can't be used as a colour set name",
             reason: :built_in_type,
             descr: descr
           )}

        # skip validated colour set
        MapSet.member?(acc.validated, name) ->
          {:ok, acc}

        true ->
          validating_context = Map.put(acc, :validating, [name])

          do_validate(descr, validating_context)
      end
    end)
    |> case do
      {:ok, _context} -> {:ok, cpnet}
      {:error, exception} when is_exception(exception) -> {:error, exception}
    end
  end

  primitive_types = Descr.__built_in_types__(:primitive)

  defp do_validate(descr, context) do
    do_validate(Descr.match(descr), descr, context)
  end

  for type <- primitive_types do
    defp do_validate({:built_in, unquote(type)}, _descr, context), do: {:ok, context}
  end

  defp do_validate({:built_in, :tuple}, {:tuple, types}, context) do
    reduce_while_and_wrap(types, context, fn descr, acc ->
      do_validate(descr, acc)
    end)
  end

  defp do_validate({:built_in, :map}, {:map, types} = descr, context) do
    reduce_while_and_wrap(types, context, fn
      {key, descr}, acc when is_atom(key) ->
        do_validate(descr, acc)

      {key, _descr}, _acc ->
        {:error,
         InvalidColourSetError.exception(
           message: "#{inspect(key)} is not a valid map key, it should be an atom",
           reason: :invalid_map_key,
           descr: descr
         )}
    end)
  end

  defp do_validate({:built_in, :enum}, {:enum, items} = descr, context) do
    items
    |> Enum.reject(&is_atom/1)
    |> case do
      [] ->
        {:ok, context}

      [item | _rest] ->
        {:error,
         InvalidColourSetError.exception(
           message: "#{inspect(item)} is not a valid enum item, it should be an atom",
           reason: :invalid_enum_item,
           descr: descr
         )}
    end
  end

  defp do_validate({:built_in, :union}, {:union, types} = descr, context) do
    reduce_while_and_wrap(types, context, fn
      {tag, descr}, acc when is_atom(tag) ->
        do_validate(descr, acc)

      {tag, _descr}, _acc ->
        {:error,
         InvalidColourSetError.exception(
           message: "#{inspect(tag)} is not a valid union tag, it should be an atom",
           reason: :invalid_union_tag,
           descr: descr
         )}
    end)
  end

  defp do_validate({:built_in, :list}, {:list, type}, context) do
    do_validate(type, context)
  end

  defp do_validate({:compound, name}, descr, context) do
    cond do
      MapSet.member?(context.validated, name) ->
        {:ok, context}

      name in context.validating ->
        dependent_paths =
          context.validating |> Enum.reverse() |> Enum.map_join(" -> ", &inspect/1)

        {:error,
         InvalidColourSetError.exception(
           message: """
           The type #{inspect(name)} is a recursive type, the dependent paths are #{dependent_paths};
           the dependency depends on itself, or cyclic dependencies are detected.
           """,
           reason: :recursive_type,
           descr: descr
         )}

      true ->
        with {:ok, descr} <- context.fetch_type.(name),
             compound_context = Map.update!(context, :validating, &[name | &1]),
             {:ok, context} <- do_validate(descr, compound_context) do
          {:ok, Map.update!(context, :validated, &MapSet.put(&1, name))}
        else
          :error ->
            {:error,
             InvalidColourSetError.exception(
               message: "the type #{inspect(name)} is undefined",
               reason: :undefined_type,
               descr: descr
             )}

          {:error, exception} = error when is_exception(exception) ->
            error
        end
    end
  end

  defp do_validate(:unknown, descr, _context) do
    {:error,
     InvalidColourSetError.exception(
       message: "The type is not supported",
       reason: :unsupported_type,
       descr: descr
     )}
  end

  @spec reduce_while_and_wrap(
          Enumerable.t(element),
          acc,
          (element, acc -> {:ok, acc} | {:error, reason})
        ) :: {:ok, acc} | {:error, reason}
        when element: var, acc: var, reason: var
  defp reduce_while_and_wrap(enumerable, acc, fun) do
    enumerable
    |> Enum.reduce_while(acc, fn item, acc ->
      case fun.(item, acc) do
        {:ok, acc} -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      acc -> {:ok, acc}
    end
  end
end
