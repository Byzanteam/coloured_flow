defmodule ColouredFlow.Runner.Storage.Schemas.Snapshot do
  @moduledoc false

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.Snapshot
  alias ColouredFlow.Runner.Storage.Schemas.Enactment

  typed_structor define_struct: false, enforce: true do
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())
    field :version, pos_integer()
    field :data, %{markings: [Marking.t()]}

    field :inserted_at, NaiveDateTime.t()
    field :updated_at, NaiveDateTime.t()
  end

  @primary_key false

  schema "snapshots" do
    belongs_to :enactment, Enactment, primary_key: true

    field :version, :integer

    embeds_one :data, Data, primary_key: false, on_replace: :update do
      @moduledoc false

      field :markings, {:array, Object}, codec: Codec.Marking
    end

    timestamps()
  end

  @spec to_snapshot(t()) :: Snapshot.t()
  def to_snapshot(%__MODULE__{} = snapshot) do
    %Snapshot{
      version: snapshot.version,
      markings: snapshot.data.markings
    }
  end
end
