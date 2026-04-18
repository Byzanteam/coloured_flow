defmodule ColouredFlow.Runner.Storage.Schemas.Flow do
  @moduledoc """
  The schema for the flow in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Definition.ColouredPetriNet

  typed_schema "flows", null: false do
    field :name, :string
    field :definition, Object, codec: Codec.ColouredPetriNet, typed: [type: ColouredPetriNet.t()]

    timestamps(updated_at: false)
  end

  @spec to_coloured_petri_net(t()) :: ColouredPetriNet.t()
  def to_coloured_petri_net(%__MODULE__{} = flow) do
    flow.definition
  end
end
