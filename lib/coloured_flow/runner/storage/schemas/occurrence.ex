defmodule ColouredFlow.Runner.Storage.Schemas.Occurrence do
  @moduledoc """
  The schema for the occurrence in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Occurrence
  alias ColouredFlow.Runner.Storage.Schemas.Enactment
  alias ColouredFlow.Runner.Storage.Schemas.Workitem

  @type step_number() :: pos_integer()

  @primary_key false

  typed_schema "occurrences", null: false do
    belongs_to :enactment, Enactment, primary_key: true
    field :step_number, :integer, primary_key: true, typed: [type: step_number()]

    belongs_to :workitem, Workitem

    field :occurrence, Object, codec: Codec.Occurrence, typed: [type: Occurrence.t()]

    timestamps(updated_at: false)
  end

  @spec to_occurrence(t()) :: Occurrence.t()
  def to_occurrence(%__MODULE__{} = occurrence) do
    occurrence.occurrence
  end
end
