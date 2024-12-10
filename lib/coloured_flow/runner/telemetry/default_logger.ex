defmodule ColouredFlow.Runner.Telemetry.DefaultLogger do
  @moduledoc false

  require Logger

  @doc false
  @spec handle_event([atom()], map(), map(), Keyword.t()) :: :ok
  def handle_event(
        [:coloured_flow, :runner, :enactment, transition],
        measurements,
        metadata,
        opts
      )
      when transition in [:start, :stop, :terminate, :exception] do
    log(:enactment, opts, fn ->
      basic =
        case transition do
          :start ->
            %{
              event: "enactment:start",
              system_time: convert_system_time(measurements.system_time)
            }

          :stop ->
            %{
              event: "enactment:stop",
              system_time: convert_system_time(measurements.system_time)
            }

          :terminate ->
            %{
              event: "enactment:terminate",
              system_time: convert_system_time(measurements.system_time),
              termination_type: metadata.termination_type,
              termination_message: Map.get(metadata, :termination_message)
            }

          :exception ->
            %{
              event: "enactment:exception",
              system_time: convert_system_time(measurements.system_time),
              exception_reason: metadata.exception_reason,
              error: Exception.format_banner(:error, metadata.exception)
            }
        end

      enactment = build_enactment_info(metadata.enactment_state)

      Map.merge(basic, enactment)
    end)
  end

  def handle_event(
        [:coloured_flow, :runner, :enactment, operation, event],
        measurements,
        metadata,
        opts
      ) do
    log(:workitem, opts, fn ->
      basic =
        case event do
          :start ->
            %{
              event: "#{operation}:start",
              system_time: convert_system_time(measurements.system_time)
            }

          :stop ->
            %{
              event: "#{operation}:stop",
              duration: convert_duration(measurements.duration)
            }

          :exception ->
            %{
              event: "#{operation}:exception",
              duration: convert_duration(measurements.duration),
              error: Exception.format_banner(metadata.kind, metadata.reason, metadata.stacktrace)
            }
        end

      enactment = build_enactment_info(metadata.enactment_state)

      extra = build_extra(operation, event, metadata)

      basic |> Map.merge(enactment) |> Map.merge(extra)
    end)
  end

  defp build_enactment_info(%ColouredFlow.Runner.Enactment{} = enactment_state) do
    %{
      enactment_id: enactment_state.enactment_id,
      enactment_version: enactment_state.version,
      enactment_markings: Map.values(enactment_state.markings),
      enactment_workitems: Map.values(enactment_state.workitems)
    }
  end

  defp build_extra(operation, event, metadata) do
    case {operation, event} do
      {:produce_workitems, :start} ->
        %{binding_elements: Enum.to_list(metadata.binding_elements)}

      {:complete_workitems, :start} ->
        %{
          workitem_ids: metadata.workitem_ids,
          workitem_id_and_outputs: Map.new(metadata.workitem_id_and_outputs)
        }

      {_operation, :start} ->
        %{workitem_ids: metadata.workitem_ids}

      {_operation, :stop} ->
        %{workitems: metadata.workitems}

      {_operation, :exception} ->
        %{}
    end
  end

  defp convert_system_time(value), do: DateTime.from_unix!(value, :native)
  defp convert_duration(value), do: System.convert_time_unit(value, :native, :microsecond)

  defp log(event_type, opts, fun) do
    level = Keyword.fetch!(opts, :level)

    Logger.log(level, fn ->
      output = Map.put(fun.(), :source, "coloured_flow.runner")

      if Keyword.fetch!(opts, :encode) do
        output
        |> encode(event_type)
        |> Jason.encode_to_iodata!()
      else
        output
      end
    end)
  end

  alias ColouredFlow.Runner.Storage.Schemas.JsonInstance.Codec
  alias ColouredFlow.Runner.Telemetry.LooseMapCodec
  alias ColouredFlow.Runner.Telemetry.MapCodec

  event_types = ~w(enactment workitem)a
  @typep event_type() :: unquote(ColouredFlow.Types.make_sum_type(event_types))

  @doc """
  Encodes the given data using the codec specification.
  """
  @spec encode(map(), event_type()) :: map()
  def encode(data, event_type) when event_type in unquote(event_types) do
    Codec.encode(codec_spec(event_type), data)
  end

  @doc """
  Decodes the given data using the codec specification.
  """
  @spec decode(map(), event_type()) :: map()
  def decode(data, event_type) when event_type in unquote(event_types) do
    Codec.decode(codec_spec(event_type), data)
  end

  @spec codec_spec(event_type()) :: Codec.codec_spec(map())
  def codec_spec(:enactment) do
    {
      :codec,
      LooseMapCodec,
      [
        source: :string,
        event: :string,
        enactment_id: :string,
        enactment_version: :integer,
        enactment_markings: {:list, {:codec, Codec.Marking}},
        enactment_workitems: {:list, workitem_spec()},
        system_time: system_time_spec(),
        termination_type: :atom,
        termination_message: :string,
        exception_reason: :atom,
        error: :string
      ]
    }
  end

  def codec_spec(:workitem) do
    {
      :codec,
      LooseMapCodec,
      [
        source: :string,
        event: :string,
        enactment_id: :string,
        enactment_version: :integer,
        enactment_markings: {:list, {:codec, Codec.Marking}},
        enactment_workitems: {:list, workitem_spec()},
        system_time: system_time_spec(),
        duration: :integer,
        error: :string,
        workitem_ids: {:list, :string},
        workitems: {:list, workitem_spec()},
        # for produce_workitems
        binding_elements: {:list, {:codec, Codec.BindingElement}},
        # for complete_workitems
        workitem_id_and_outputs: workitem_id_and_outputs_spec()
      ]
    }
  end

  defp system_time_spec do
    {:codec,
     {
       fn dt -> DateTime.to_iso8601(dt) end,
       fn dt_str ->
         {:ok, dt, 0} = DateTime.from_iso8601(dt_str)
         dt
       end
     }}
  end

  defp workitem_spec do
    {:codec, MapCodec,
     [
       id: :string,
       state: :atom,
       binding_element: {:codec, Codec.BindingElement}
     ]}
  end

  defp workitem_id_and_outputs_spec do
    output_spec = {:list, Codec.BindingElement.binding_codec_spec()}

    {:codec,
     {
       fn map -> Map.new(map, fn {key, value} -> {key, Codec.encode(output_spec, value)} end) end,
       fn map -> Map.new(map, fn {key, value} -> {key, Codec.decode(output_spec, value)} end) end
     }}
  end
end
