defmodule ColouredFlow.Runner.Storage.Schemas.Snapshot do
  @moduledoc """
  The schema for the snapshot in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  typed_structor define_struct: false, enforce: true do
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())

    field :version, pos_integer()
    field :markings, [Marking.t()]

    field :inserted_at, DateTime.t()
    field :updated_at, DateTime.t()
  end

  @primary_key false

  schema "snapshots" do
    belongs_to :enactment, Enactment, primary_key: true

    field :version, :integer
    field :markings, {:array, Object}, codec: Codec.Marking

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
