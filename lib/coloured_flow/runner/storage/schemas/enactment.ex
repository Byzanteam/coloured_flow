defmodule ColouredFlow.Runner.Storage.Schemas.Enactment do
  @moduledoc false

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Storage.Schemas.Flow
  alias ColouredFlow.Runner.Storage.Schemas.Occurrence

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :flow_id, Types.id()
    field :flow, Types.association(Flow.t())
    field :state, :running | :exception | :terminated, default: :running
    field :label, String.t(), enforce: false

    field :data, %{
      required(:initial_markings) => [Marking.t()],
      optional(:final_markings) => [Marking.t()]
    }

    field :steps, Types.association([Occurrence.t()])

    field :inserted_at, NaiveDateTime.t()
    field :updated_at, NaiveDateTime.t()
  end

  schema "enactments" do
    belongs_to :flow, Flow

    field :state, Ecto.Enum, values: [:running, :exception, :terminated], default: :running
    field :label, :string

    embeds_one :data, Data, primary_key: false, on_replace: :delete do
      @moduledoc false

      field :initial_markings, {:array, Object}, codec: Codec.Marking
      field :final_markings, {:array, Object}, codec: Codec.Marking
    end

    has_many :steps, Occurrence

    timestamps()
  end

  @spec to_initial_markings(t()) :: [Marking.t()]
  def to_initial_markings(%__MODULE__{} = enactment) do
    enactment.data.initial_markings
  end
end
