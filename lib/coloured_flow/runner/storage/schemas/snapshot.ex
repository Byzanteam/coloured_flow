defmodule ColouredFlow.Runner.Storage.Schemas.Snapshot do
  @moduledoc """
  The schema for the snapshot in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  @primary_key false

  typed_schema "snapshots", null: false do
    belongs_to :enactment, Enactment, primary_key: true

    field :version, :integer, typed: [type: pos_integer()]
    field :markings, {:array, Object}, codec: Codec.Marking, typed: [type: [Marking.t()]]

    timestamps()
  end

  @spec to_snapshot(t()) :: Snapshot.t()
  def to_snapshot(%__MODULE__{} = snapshot) do
    %Snapshot{
      version: snapshot.version,
      markings: snapshot.markings
    }
  end
end
