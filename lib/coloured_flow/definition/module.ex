defmodule ColouredFlow.Definition.Module do
  @moduledoc """
  A module represents a reusable subnet that can be instantiated by substitution transitions.

  Modules enable hierarchical composition and reuse in Coloured Petri Nets.
  A module is essentially a complete CPN with designated port places that define its interface.

  ## Key Concepts

  - **Port Places**: Special places that define the module's input/output interface
  - **Substitution Transition**: A transition in the parent net that references this module
  - **Socket Assignment**: Mapping between parent net places and module port places
  - **Module Instance**: A runtime instantiation of a module with its own state

  ## Example

  A simple authentication module might have:
  - Input port: `credentials` (username/password)
  - Output ports: `authenticated`, `failed`
  - Internal places and transitions for the authentication logic

  This module can then be instantiated multiple times in different workflows.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Arc
  alias ColouredFlow.Definition.ColourSet
  alias ColouredFlow.Definition.Constant
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.PortPlace
  alias ColouredFlow.Definition.Procedure
  alias ColouredFlow.Definition.Transition
  alias ColouredFlow.Definition.Variable

  @type name() :: binary()

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :name, name(),
      doc: "Unique name of the module."

    # Data types (inherited or module-specific)
    field :colour_sets, [ColourSet.t()],
      default: [],
      doc: "Colour sets specific to this module."

    # Port places - the interface of the module
    field :port_places, [PortPlace.t()],
      default: [],
      doc: "Port places that define the module's interface."

    # Internal net structure
    field :places, [Place.t()],
      default: [],
      doc: "Internal places of the module (non-port places)."

    field :transitions, [Transition.t()],
      default: [],
      doc: "Transitions within the module."

    field :arcs, [Arc.t()],
      default: [],
      doc: "Arcs connecting places and transitions within the module."

    # Variables and constants
    field :variables, [Variable.t()],
      default: [],
      doc: "Variables used in the module."

    field :constants, [Constant.t()],
      default: [],
      doc: "Constants used in the module."

    field :functions, [Procedure.t()],
      default: [],
      doc: "Functions/procedures defined in the module."
  end

  @doc """
  Returns all places in the module (both port places and internal places).
  """
  @spec all_places(t()) :: [Place.t() | PortPlace.t()]
  def all_places(%__MODULE__{port_places: port_places, places: places}) do
    port_places ++ places
  end

  @doc """
  Gets a port place by name.
  """
  @spec get_port_place(t(), PortPlace.name()) :: PortPlace.t() | nil
  def get_port_place(%__MODULE__{port_places: port_places}, name) do
    Enum.find(port_places, &(&1.name == name))
  end

  @doc """
  Returns all input port places.
  """
  @spec input_ports(t()) :: [PortPlace.t()]
  def input_ports(%__MODULE__{port_places: port_places}) do
    Enum.filter(port_places, &PortPlace.input?/1)
  end

  @doc """
  Returns all output port places.
  """
  @spec output_ports(t()) :: [PortPlace.t()]
  def output_ports(%__MODULE__{port_places: port_places}) do
    Enum.filter(port_places, &PortPlace.output?/1)
  end
end
