defmodule ColouredFlow.Runner.Storage.Schemas.Workitem do
  @moduledoc """
  The schema for the workitem in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  states = ~w[enabled started completed withdrawn]a

  @type state() :: unquote(ColouredFlow.Types.make_sum_type(states))

  typed_schema "workitems", null: false do
    belongs_to :enactment, Enactment

    field :state, Ecto.Enum, values: states, typed: [type: state()]
    field :binding_element, Object, codec: Codec.BindingElement, typed: [type: BindingElement.t()]

    timestamps()
  end

  @spec to_workitem(t()) :: Workitem.t()
  def to_workitem(%__MODULE__{} = workitem) do
    %Workitem{
      id: workitem.id,
      state: workitem.state,
      binding_element: workitem.binding_element
    }
  end
end
