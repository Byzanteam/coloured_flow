defmodule ColouredFlowDashboard.WorkitemCompletion do
  @moduledoc """
  Shared coerce + dispatch path for the `:complete_workitem` Musubi command.

  Both `ColouredFlowDashboardWeb.Stores.InboxStore` and
  `ColouredFlowDashboardWeb.Stores.EnactmentDetailStore` expose
  `:complete_workitem`; they only differ in how they look up the per-workitem
  meta (enactment id + output-variable schema). Once the meta is resolved,
  the wire-payload → runner-call path is identical — this module owns it so
  reply codes, exception flattening, and atom-safety stay in lockstep.

  ## Reply codes

  Same shape on both stores:

    * `:ok`
    * `:already_completed`   — workitem id no longer live (completed/withdrawn).
    * `:unknown_workitem`    — id not tracked on this page.
    * `:unknown_variable`    — payload key not in the transition's output schema,
                               OR not an existing atom on the BEAM.
    * `:invalid_outputs`     — payload `outputs` was not a JSON object.
    * `:type_mismatch`       — value's wire shape does not match the declared
                               colour-set kind. Reply carries `:variable` and
                               `:expected_kind`.
    * `:invalid_elixir`      — `:elixir` text rejected by the parser or
                               literal-only walker. Reply carries `:variable`
                               and `:message`.
    * `:runner_error`        — any other exception from the runner; reason
                               surfaced in `:message`.
  """

  alias ColouredFlow.Runner.Enactment.Workitem, as: RunnerWorkitem
  alias ColouredFlow.Runner.Enactment.WorkitemTransition
  alias ColouredFlow.Runner.Exceptions.InvalidWorkitemTransition
  alias ColouredFlow.Runner.Exceptions.NonLiveWorkitem
  alias ColouredFlowDashboard.OutputSchemaBuilder
  alias ColouredFlowDashboardWeb.Views.OutputVar

  @type schema :: %{optional(String.t()) => OutputVar.t()}
  @type meta :: %{required(:enactment_id) => String.t(), required(:schema) => schema()}

  @doc """
  Complete a workitem with the operator-supplied outputs.

  `meta` is `nil` when the caller could not locate the workitem in its
  per-page index (stale row on the client). `outputs_json` is the
  unwrapped payload value as it came off the wire — usually a `map()`,
  but the guard branches handle other shapes so callers can pass the
  raw payload directly without pre-validation.
  """
  @spec complete(meta() | nil, String.t() | nil, term()) :: map()
  def complete(nil, workitem_id, _outputs) do
    %{code: :unknown_workitem, workitem_id: workitem_id}
  end

  def complete(%{enactment_id: enactment_id, schema: schema}, workitem_id, outputs_json)
      when is_binary(workitem_id) do
    with {:ok, outputs_map} <- ensure_map(outputs_json),
         {:ok, free_binding} <- coerce_outputs(outputs_map, schema) do
      dispatch_completion(enactment_id, workitem_id, free_binding)
    else
      {:error, :invalid_outputs} ->
        %{code: :invalid_outputs, message: "outputs must be a JSON object"}

      {:error, {:unknown_variable, key}} ->
        %{code: :unknown_variable, variable: key}

      {:error, {:type_mismatch, key, expected}} ->
        %{
          code: :type_mismatch,
          variable: key,
          expected_kind: expected,
          message: "Output `#{key}` must be a #{expected}."
        }

      {:error, {:unknown_enum, key, value}} ->
        %{
          code: :type_mismatch,
          variable: key,
          expected_kind: "enum",
          message: "Output `#{key}` does not accept value #{inspect(value)}."
        }

      {:error, {:invalid_elixir, key, reason}} ->
        %{
          code: :invalid_elixir,
          variable: key,
          message: "Output `#{key}` is not a valid Elixir term literal: #{reason}"
        }
    end
  end

  def complete(_meta, workitem_id, _outputs_json) do
    %{code: :unknown_workitem, workitem_id: workitem_id}
  end

  @doc """
  Build the per-workitem `meta` map a store keeps alongside its row index.

  `schema_list` is the `output_vars` field of a `WorkitemRow` (a list of
  `%OutputVar{}`). The map keys the schema by string `name` so payload
  lookups stay O(1).
  """
  @spec build_meta(String.t(), [OutputVar.t()]) :: meta()
  def build_meta(enactment_id, schema_list)
      when is_binary(enactment_id) and is_list(schema_list) do
    %{enactment_id: enactment_id, schema: index_schema(schema_list)}
  end

  defp index_schema(schema_list) when is_list(schema_list) do
    Map.new(schema_list, fn %OutputVar{name: name} = var -> {name, var} end)
  end

  defp ensure_map(map) when is_map(map), do: {:ok, map}
  defp ensure_map(_other), do: {:error, :invalid_outputs}

  # Schema-strict — every key in `outputs_map` MUST match a free variable
  # declared by the transition's schema. `OutputSchemaBuilder.coerce_value/2`
  # passes `nil` schemas through (used by the cpnet-introspection path when
  # building the form hint), which would silently let an operator submit
  # outputs the runner then drops. Reject unknown keys here so the SPA can
  # surface a structured `:unknown_variable` reply.
  defp coerce_outputs(outputs_map, schema) when is_map(outputs_map) and is_map(schema) do
    Enum.reduce_while(outputs_map, {:ok, []}, fn {key, value}, {:ok, acc} ->
      key_str = to_string(key)

      case Map.fetch(schema, key_str) do
        {:ok, %OutputVar{} = var} -> coerce_known_key(key, key_str, value, var, acc)
        :error -> {:halt, {:error, {:unknown_variable, key_str}}}
      end
    end)
  end

  defp coerce_known_key(key, key_str, value, %OutputVar{} = var, acc) do
    with {:ok, atom} <- to_existing_atom_safe(key),
         {:ok, coerced} <- OutputSchemaBuilder.coerce_value(var, value) do
      {:cont, {:ok, [{atom, coerced} | acc]}}
    else
      :error ->
        {:halt, {:error, {:unknown_variable, key_str}}}

      {:error, {:type_mismatch, expected}} ->
        {:halt, {:error, {:type_mismatch, key_str, expected}}}

      {:error, {:unknown_enum, value}} ->
        {:halt, {:error, {:unknown_enum, key_str, value}}}

      {:error, {:invalid_elixir, reason}} ->
        {:halt, {:error, {:invalid_elixir, key_str, reason}}}
    end
  end

  defp to_existing_atom_safe(key) when is_atom(key), do: {:ok, key}

  defp to_existing_atom_safe(key) when is_binary(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end

  defp to_existing_atom_safe(_other), do: :error

  defp dispatch_completion(enactment_id, workitem_id, free_binding) do
    case WorkitemTransition.complete_workitem(enactment_id, {workitem_id, free_binding}) do
      {:ok, %RunnerWorkitem{}} ->
        %{code: :ok}

      {:error, %InvalidWorkitemTransition{}} ->
        %{code: :already_completed, workitem_id: workitem_id}

      {:error, %NonLiveWorkitem{}} ->
        %{code: :already_completed, workitem_id: workitem_id}

      {:error, exception} when is_exception(exception) ->
        %{code: :runner_error, message: Exception.message(exception)}
    end
  catch
    :exit, {:noproc, _info} -> %{code: :already_completed, workitem_id: workitem_id}
    kind, reason -> %{code: :runner_error, message: Exception.format(kind, reason)}
  end
end
