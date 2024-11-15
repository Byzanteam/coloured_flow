defmodule ColouredFlow.Runner.Storage.Schemas.Flow do
  @moduledoc false

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Definition.ColouredPetriNet

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :name, String.t()
    field :data, %{definition: ColouredPetriNet.t()}

    field :inserted_at, NaiveDateTime.t()
  end

  schema "flows" do
    field :name, :string

    embeds_one :data, Data, primary_key: false, on_replace: :update do
      @moduledoc false

      field :definition, Object, codec: Codec.ColouredPetriNet
    end

    timestamps(updated_at: false)
  end

  @spec to_coloured_petri_net(t()) :: ColouredPetriNet.t()
  def to_coloured_petri_net(%__MODULE__{} = flow) do
    flow.data.definition
  end
end
