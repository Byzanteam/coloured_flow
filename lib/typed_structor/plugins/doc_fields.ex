defmodule TypedStructor.Plugins.DocFields do
  @moduledoc false

  use TypedStructor.Plugin

  @impl TypedStructor.Plugin
  defmacro before_definition(definition, _opts) do
    caller = Macro.escape(__CALLER__)

    quote do
      @typedoc unquote(__MODULE__).__generate_doc__(
                 unquote(caller),
                 unquote(definition),
                 elem(
                   Module.get_attribute(
                     __MODULE__,
                     :typedoc,
                     {0, "The `#{inspect(__MODULE__)}` struct."}
                   ),
                   1
                 )
               )

      unquote(definition)
    end
  end

  def __generate_doc__(caller, definition, typedoc) do
    parameters =
      Enum.map(definition.parameters, fn parameter ->
        name = Keyword.fetch!(parameter, :name)
        doc = Keyword.get(parameter, :doc, "*not documented*")

        ["**`#{inspect(name)}`**", doc]
      end)

    parameters_docs =
      if length(parameters) > 0 do
        """
        ## Parameters

        #{join_rows(parameters)}
        """
      end

    enforce = Keyword.get(definition.options, :enforce, false)

    fields =
      Enum.map(definition.fields, fn field ->
        name = Keyword.fetch!(field, :name)

        type = Keyword.fetch!(field, :type)

        type =
          if Keyword.get(field, :enforce, enforce) or Keyword.has_key?(field, :default) do
            expand_type(type, caller)
          else
            "#{expand_type(type, caller)} | nil"
          end

        doc = Keyword.get(field, :doc, "*not documented*")

        ["### **`#{inspect(name)}`**", "```\n#{type}\n```", doc]
      end)

    fields_docs =
      if length(fields) > 0 do
        """
        ## Fields

        #{join_rows(fields)}
        """
      end

    [parameters_docs, fields_docs]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        typedoc

      docs ->
        """
        #{typedoc}

        #{Enum.join(docs, "\n\n")}
        """
    end
  end

  defp expand_type(type, caller) do
    type
    |> Macro.prewalk(&Macro.expand(&1, caller))
    |> Macro.to_string()
  end

  defp join_rows(rows) do
    Enum.map_join(rows, "\n\n", fn parts -> Enum.join(parts, "\n\n") end)
  end
end
