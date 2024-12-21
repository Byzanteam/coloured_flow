defmodule ColouredFlow.Runner.Storage.Schemas.Flow do
  @moduledoc """
  The schema for the flow in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Definition.ColouredPetriNet

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :name, String.t()
    field :definition, ColouredPetriNet.t()

    field :inserted_at, DateTime.t()
  end

  schema "flows" do
    field :name, :string
    field :definition, Object, codec: Codec.ColouredPetriNet

    timestamps(updated_at: false)
  end

  @spec to_coloured_petri_net(t()) :: ColouredPetriNet.t()
  def to_coloured_petri_net(%__MODULE__{} = flow) do
    flow.definition
  end
end
