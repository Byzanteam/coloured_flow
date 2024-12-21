defmodule ColouredFlow.Runner.Storage.Schemas.Occurrence do
  @moduledoc """
  The schema for the occurrence in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Storage.Schemas.Enactment
  alias ColouredFlow.Runner.Storage.Schemas.Workitem

  @type step_number() :: pos_integer()

  typed_structor define_struct: false, enforce: true do
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())
    field :step_number, step_number()

    field :workitem_id, Types.id()
    field :workitem, Types.association(Workitem.t())

    field :occurrence, Occurrence.t()

    field :inserted_at, DateTime.t()
  end

  @primary_key false

  schema "occurrences" do
    belongs_to :enactment, Enactment, primary_key: true
    field :step_number, :integer, primary_key: true

    belongs_to :workitem, Workitem

    field :occurrence, Object, codec: Codec.Occurrence

    timestamps(updated_at: false)
  end

  @spec to_occurrence(t()) :: Occurrence.t()
  def to_occurrence(%__MODULE__{} = occurrence) do
    occurrence.occurrence
  end
end
