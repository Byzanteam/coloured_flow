defmodule ColouredFlow.Runner.Storage.Schemas.Occurrence do
  @moduledoc false

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Storage.Schemas.Enactment
  alias ColouredFlow.Runner.Storage.Schemas.Workitem

  @type step_number() :: pos_integer()

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())
    field :workitem, Types.association(Workitem.t())
    field :step_number, step_number()
    field :data, %{occurrence: Occurrence.t()}

    field :inserted_at, NaiveDateTime.t()
  end

  schema "occurrences" do
    belongs_to :enactment, Enactment
    belongs_to :workitem, Workitem
    field :step_number, :integer

    embeds_one :data, Data, primary_key: false, on_replace: :update do
      @moduledoc false

      field :occurrence, Object, codec: Codec.Occurrence
    end

    timestamps(updated_at: false)
  end

  @spec to_occurrence(t()) :: Occurrence.t()
  def to_occurrence(%__MODULE__{} = occurrence) do
    occurrence.data.occurrence
  end
end
