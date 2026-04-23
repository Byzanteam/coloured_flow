defmodule ColouredFlow.Enactment.ModuleInstance do
  @moduledoc """
  Represents a runtime instance of a module.

  A module instance is created when a substitution transition fires.
  It maintains the state of the module execution including:
  - The module definition being executed
  - The current marking of the module's places
  - The mapping between parent sockets and module ports
  - The execution state (running, completed, failed)
  """

  use TypedStructor

  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.SocketAssignment
  alias ColouredFlow.Enactment.Marking

  @type instance_id() :: binary()
  @type state() :: :initializing | :running | :completed | :failed

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :id, instance_id(),
      doc: "Unique identifier for this module instance."

    field :module_name, Module.name(),
      doc: "The name of the module being instantiated."

    field :socket_assignments, [SocketAssignment.t()],
      doc: "Mapping between parent net sockets and module ports."

    field :markings, %{binary() => Marking.tokens()},
      default: %{},
      doc: "Current marking of the module's places (both port and internal)."

    field :state, state(),
      default: :initializing,
      doc: "Current execution state of the module instance."

    field :parent_enactment_id, binary(),
      enforce: false,
      doc: "ID of the parent enactment that created this instance."

    field :parent_transition, binary(),
      enforce: false,
      doc: "Name of the substitution transition that created this instance."
  end

  @doc """
  Creates a new module instance.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts) do
    id = Keyword.get(opts, :id, generate_id())
    module_name = Keyword.fetch!(opts, :module_name)
    socket_assignments = Keyword.fetch!(opts, :socket_assignments)

    %__MODULE__{
      id: id,
      module_name: module_name,
      socket_assignments: socket_assignments,
      markings: %{},
      state: :initializing,
      parent_enactment_id: Keyword.get(opts, :parent_enactment_id),
      parent_transition: Keyword.get(opts, :parent_transition)
    }
  end

  @doc """
  Checks if the module instance is running.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{state: state}), do: state == :running

  @doc """
  Checks if the module instance is completed.
  """
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{state: state}), do: state == :completed

  @doc """
  Checks if the module instance has failed.
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{state: state}), do: state == :failed

  @doc """
  Marks the module instance as running.
  """
  @spec mark_running(t()) :: t()
  def mark_running(%__MODULE__{} = instance), do: %{instance | state: :running}

  @doc """
  Marks the module instance as completed.
  """
  @spec mark_completed(t()) :: t()
  def mark_completed(%__MODULE__{} = instance), do: %{instance | state: :completed}

  @doc """
  Marks the module instance as failed.
  """
  @spec mark_failed(t()) :: t()
  def mark_failed(%__MODULE__{} = instance), do: %{instance | state: :failed}

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
