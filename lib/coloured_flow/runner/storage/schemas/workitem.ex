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
  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())

    field :state, state()
    field :binding_element, BindingElement.t()

    field :inserted_at, DateTime.t()
    field :updated_at, DateTime.t()
  end

  schema "workitems" do
    belongs_to :enactment, Enactment

    field :state, Ecto.Enum, values: states
    field :binding_element, Object, codec: Codec.BindingElement

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
