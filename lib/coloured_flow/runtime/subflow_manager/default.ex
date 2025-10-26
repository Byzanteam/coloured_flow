defmodule ColouredFlow.Runtime.SubFlowManager.Default do
  @moduledoc """
  Default SubFlowManager implementation.

  Loads modules from the database using FlowConverter and manages child enactments
  through the ColouredFlow runtime.

  ## Configuration

  The default manager requires an Ecto repo for loading flows from the database.

  ## Example

      # Application startup
      manager = SubFlowManager.Default.new(repo: MyApp.Repo)

      # Use in enactment
      {:ok, module} = SubFlowManager.resolve_module(
        manager,
        {:module_ref, flow_id: 123, port_specs: [...]},
        []
      )
  """

  alias ColouredFlow.Builder.FlowConverter
  alias ColouredFlow.Runtime.ModuleReference
  alias ColouredFlow.Runner.Storage.Schemas

  defstruct [:repo]

  @type t :: %__MODULE__{
          repo: module()
        }

  @doc """
  Create a new default SubFlowManager.

  ## Options

  - `:repo` (required) - Ecto repo for loading flows from database

  ## Example

      manager = SubFlowManager.Default.new(repo: MyApp.Repo)
  """
  @spec new(Keyword.t()) :: t()
  def new(opts) do
    repo = Keyword.fetch!(opts, :repo)

    %__MODULE__{
      repo: repo
    }
  end
end

defimpl ColouredFlow.Runtime.SubFlowManager, for: ColouredFlow.Runtime.SubFlowManager.Default do
  alias ColouredFlow.Builder.FlowConverter
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Runner.Storage.Schemas

  @impl true
  def resolve_module(%{repo: repo}, module_ref, _options) do
    case module_ref do
      {:module_ref, ref_opts} ->
        resolve_from_ref_opts(ref_opts, repo)

      _ ->
        {:error, {:invalid_module_ref, "Unknown module reference format: #{inspect(module_ref)}"}}
    end
  end

  @impl true
  def start_child_enactment(_manager, _module, _initial_marking, _options) do
    # TODO: Implement child enactment starting
    # This will require integration with the Enactment GenServer
    {:error, :not_implemented}
  end

  @impl true
  def get_child_state(_manager, _child_id) do
    # TODO: Implement child state querying
    {:error, :not_implemented}
  end

  # Private functions

  defp resolve_from_ref_opts(ref_opts, repo) do
    cond do
      Keyword.has_key?(ref_opts, :flow_id) and Keyword.has_key?(ref_opts, :port_specs) ->
        flow_id = Keyword.fetch!(ref_opts, :flow_id)
        port_specs = Keyword.fetch!(ref_opts, :port_specs)
        module_name = build_module_name("flow_#{flow_id}")

        load_from_flow_id(flow_id, module_name, port_specs, repo)

      Keyword.has_key?(ref_opts, :flow_id) and Keyword.has_key?(ref_opts, :module_name) ->
        flow_id = Keyword.fetch!(ref_opts, :flow_id)
        module_name = Keyword.fetch!(ref_opts, :module_name)

        load_from_flow_id_auto(flow_id, module_name, repo)

      Keyword.has_key?(ref_opts, :flow_name) and Keyword.has_key?(ref_opts, :port_specs) ->
        flow_name = Keyword.fetch!(ref_opts, :flow_name)
        port_specs = Keyword.fetch!(ref_opts, :port_specs)
        module_name = build_module_name(flow_name)

        load_from_flow_name(flow_name, module_name, port_specs, repo)

      Keyword.has_key?(ref_opts, :flow_name) and Keyword.has_key?(ref_opts, :module_name) ->
        flow_name = Keyword.fetch!(ref_opts, :flow_name)
        module_name = Keyword.fetch!(ref_opts, :module_name)

        load_from_flow_name_auto(flow_name, module_name, repo)

      true ->
        {:error, {:invalid_module_ref, "Unknown module reference format: #{inspect(ref_opts)}"}}
    end
  end

  defp build_module_name(base_name) do
    "#{base_name}_module"
  end

  defp load_from_flow_id(flow_id, module_name, port_specs, repo) do
    with {:ok, flow} <- fetch_flow_by_id(flow_id, repo),
         {:ok, module} <- convert_flow_to_module(flow, module_name, port_specs) do
      {:ok, module}
    end
  end

  defp load_from_flow_id_auto(flow_id, module_name, repo) do
    with {:ok, flow} <- fetch_flow_by_id(flow_id, repo) do
      module = FlowConverter.flow_to_module_auto(flow.definition, module_name)
      {:ok, module}
    end
  end

  defp load_from_flow_name(flow_name, module_name, port_specs, repo) do
    with {:ok, flow} <- fetch_flow_by_name(flow_name, repo),
         {:ok, module} <- convert_flow_to_module(flow, module_name, port_specs) do
      {:ok, module}
    end
  end

  defp load_from_flow_name_auto(flow_name, module_name, repo) do
    with {:ok, flow} <- fetch_flow_by_name(flow_name, repo) do
      module = FlowConverter.flow_to_module_auto(flow.definition, module_name)
      {:ok, module}
    end
  end

  defp fetch_flow_by_id(flow_id, repo) do
    case repo.get(Schemas.Flow, flow_id) do
      nil -> {:error, {:flow_not_found, flow_id}}
      flow -> {:ok, flow}
    end
  end

  defp fetch_flow_by_name(flow_name, repo) do
    import Ecto.Query

    query = from(f in Schemas.Flow, where: f.name == ^flow_name)

    case repo.one(query) do
      nil -> {:error, {:flow_not_found, flow_name}}
      flow -> {:ok, flow}
    end
  end

  defp convert_flow_to_module(flow, module_name, port_specs) do
    module =
      FlowConverter.flow_to_module(
        flow.definition,
        name: module_name,
        port_specs: port_specs
      )

    {:ok, module}
  rescue
    error -> {:error, {:conversion_failed, error}}
  end
end
