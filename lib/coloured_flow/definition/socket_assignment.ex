defmodule ColouredFlow.Definition.SocketAssignment do
  @moduledoc """
  A socket assignment maps a place in the parent net (socket) to a port place in a module.

  When a substitution transition fires, tokens flow between the socket places
  in the parent net and the port places in the module instance according to these assignments.
  """

  use TypedStructor

  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Definition.PortPlace

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :socket, Place.name(),
      doc: "The name of the place in the parent net (socket)."

    field :port, PortPlace.name(),
      doc: "The name of the port place in the module."
  end
end
