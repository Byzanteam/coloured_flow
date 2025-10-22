defmodule ColouredFlow.Builder.ModuleHelper do
  @moduledoc """
  Helper functions for building modules and substitution transitions.

  This module provides convenient functions to create module definitions,
  port places, socket assignments, and substitution transitions.
  """

  alias ColouredFlow.Definition.Action
  alias ColouredFlow.Definition.Module
  alias ColouredFlow.Definition.PortPlace
  alias ColouredFlow.Definition.SocketAssignment
  alias ColouredFlow.Definition.Transition

  @doc """
  Builds a module with the given parameters.

  ## Examples

      iex> build_module!(
      ...>   name: "authentication",
      ...>   port_places: [
      ...>     %PortPlace{name: "credentials_in", colour_set: :credentials, port_type: :input},
      ...>     %PortPlace{name: "result_out", colour_set: :boolean, port_type: :output}
      ...>   ],
      ...>   places: [
      ...>     %Place{name: "verify", colour_set: :credentials}
      ...>   ]
      ...> )
  """
  @spec build_module!(Keyword.t()) :: Module.t()
  def build_module!(params) do
    params =
      Keyword.validate!(params, [
        :name,
        colour_sets: [],
        port_places: [],
        places: [],
        transitions: [],
        arcs: [],
        variables: [],
        constants: [],
        functions: []
      ])

    struct!(Module, params)
  end

  @doc """
  Builds a port place with the given parameters.

  ## Examples

      iex> build_port_place!(
      ...>   name: "input_data",
      ...>   colour_set: :string,
      ...>   port_type: :input
      ...> )
  """
  @spec build_port_place!(Keyword.t()) :: PortPlace.t()
  def build_port_place!(params) do
    params = Keyword.validate!(params, [:name, :colour_set, :port_type])
    struct!(PortPlace, params)
  end

  @doc """
  Builds multiple port places.

  ## Examples

      iex> build_port_places!([
      ...>   [name: "input", colour_set: :string, port_type: :input],
      ...>   [name: "output", colour_set: :string, port_type: :output]
      ...> ])
  """
  @spec build_port_places!([Keyword.t()]) :: [PortPlace.t()]
  def build_port_places!(params_list) when is_list(params_list) do
    Enum.map(params_list, &build_port_place!/1)
  end

  @doc """
  Builds a socket assignment mapping a parent place to a module port.

  ## Examples

      iex> build_socket_assignment!(
      ...>   socket: "parent_place",
      ...>   port: "module_port"
      ...> )
  """
  @spec build_socket_assignment!(Keyword.t()) :: SocketAssignment.t()
  def build_socket_assignment!(params) do
    params = Keyword.validate!(params, [:socket, :port])
    struct!(SocketAssignment, params)
  end

  @doc """
  Builds multiple socket assignments.

  ## Examples

      iex> build_socket_assignments!([
      ...>   [socket: "place_a", port: "port_a"],
      ...>   [socket: "place_b", port: "port_b"]
      ...> ])
  """
  @spec build_socket_assignments!([Keyword.t()]) :: [SocketAssignment.t()]
  def build_socket_assignments!(params_list) when is_list(params_list) do
    Enum.map(params_list, &build_socket_assignment!/1)
  end

  @doc """
  Builds a substitution transition that references a module.

  ## Examples

      iex> build_substitution_transition!(
      ...>   name: "auth",
      ...>   subst: "authentication_module",
      ...>   socket_assignments: [
      ...>     %SocketAssignment{socket: "user_creds", port: "credentials_in"},
      ...>     %SocketAssignment{socket: "auth_result", port: "result_out"}
      ...>   ]
      ...> )
  """
  @spec build_substitution_transition!(Keyword.t()) :: Transition.t()
  def build_substitution_transition!(params) do
    params =
      Keyword.validate!(params, [
        :name,
        :subst,
        guard: nil,
        action: %Action{},
        socket_assignments: []
      ])

    # Substitution transitions typically don't have complex actions
    # since the work is done by the module
    params =
      params
      |> Keyword.update(:action, %Action{}, fn
        %Action{} = action -> action
        action_params when is_list(action_params) -> struct!(Action, action_params)
      end)

    struct!(Transition, params)
  end

  @doc """
  Convenient function to build a simple input port place.
  """
  @spec input_port(name :: binary(), colour_set :: atom()) :: PortPlace.t()
  def input_port(name, colour_set) do
    %PortPlace{name: name, colour_set: colour_set, port_type: :input}
  end

  @doc """
  Convenient function to build a simple output port place.
  """
  @spec output_port(name :: binary(), colour_set :: atom()) :: PortPlace.t()
  def output_port(name, colour_set) do
    %PortPlace{name: name, colour_set: colour_set, port_type: :output}
  end

  @doc """
  Convenient function to build a simple I/O port place.
  """
  @spec io_port(name :: binary(), colour_set :: atom()) :: PortPlace.t()
  def io_port(name, colour_set) do
    %PortPlace{name: name, colour_set: colour_set, port_type: :io}
  end

  @doc """
  Convenient function to build a socket assignment.
  """
  @spec socket(socket :: binary(), port :: binary()) :: SocketAssignment.t()
  def socket(socket, port) do
    %SocketAssignment{socket: socket, port: port}
  end
end
