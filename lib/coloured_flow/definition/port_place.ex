defmodule ColouredFlow.Definition.PortPlace do
  @moduledoc """
  A port place is a special place that defines the interface of a module.

  Port places allow communication between a module and its parent net.
  There are three types of port places:
  - Input: receives tokens from the parent net
  - Output: sends tokens to the parent net
  - I/O: bidirectional communication

  In the parent net, regular places are connected to these port places through
  socket assignments in substitution transitions.
  """

  use TypedStructor

  alias ColouredFlow.Definition.ColourSet

  @type name() :: binary()
  @type port_type() :: :input | :output | :io

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :name, name()

    field :colour_set, ColourSet.name(),
      doc: "The data type of the tokens that can be stored in the place."

    field :port_type, port_type(),
      doc: """
      The type of the port:
      - `:input`: receives tokens from parent net (input port)
      - `:output`: sends tokens to parent net (output port)
      - `:io`: bidirectional communication (input/output port)
      """
  end

  @doc """
  Checks if a port place is an input port (can receive tokens from parent).
  """
  @spec input?(t()) :: boolean()
  def input?(%__MODULE__{port_type: port_type}), do: port_type in [:input, :io]

  @doc """
  Checks if a port place is an output port (can send tokens to parent).
  """
  @spec output?(t()) :: boolean()
  def output?(%__MODULE__{port_type: port_type}), do: port_type in [:output, :io]
end
