defmodule ColouredFlow.Runner.Storage.Schemas.Workitem do
  @moduledoc false

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  states = ~w[offered allocated started completed withdrawn]a

  @type state() :: unquote(Types.make_sum_type(states))
  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())
    field :state, state()
    field :data, %{binding_element: BindingElement.t()}

    field :inserted_at, NaiveDateTime.t()
    field :updated_at, NaiveDateTime.t()
  end

  schema "workitems" do
    belongs_to :enactment, Enactment
    field :state, Ecto.Enum, values: states

    embeds_one :data, Data, primary_key: false, on_replace: :update do
      @moduledoc false

      field :binding_element, Object, codec: Codec.BindingElement
    end

    timestamps()
  end

  @spec to_workitem(t()) :: Workitem.t()
  def to_workitem(%__MODULE__{} = workitem) do
    %Workitem{
      id: workitem.id,
      state: workitem.state,
      binding_element: workitem.data.binding_element
    }
  end
end
