defmodule ColouredFlow.Runner.Storage.Schemas.Enactment do
  @moduledoc """
  The schema for the enactment in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Storage.Schemas.Flow
  alias ColouredFlow.Runner.Storage.Schemas.Occurrence

  states = ~w[running  exception terminated]a

  @type state() :: unquote(ColouredFlow.Types.make_sum_type(states))

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :flow_id, Types.id()
    field :flow, Types.association(Flow.t())

    field :state, state(), default: :running
    field :label, String.t(), enforce: false
    field :initial_markings, [Marking.t()]
    field :final_markings, [Marking.t()], enforce: false

    field :steps, Types.association([Occurrence.t()])

    field :inserted_at, DateTime.t()
    field :updated_at, DateTime.t()
  end

  schema "enactments" do
    belongs_to :flow, Flow

    field :state, Ecto.Enum, values: [:running, :exception, :terminated], default: :running
    field :label, :string
    field :initial_markings, {:array, Object}, codec: Codec.Marking
    field :final_markings, {:array, Object}, codec: Codec.Marking

    has_many :steps, Occurrence

    timestamps()
  end

  @spec __states__() :: [state()]
  def __states__, do: unquote(states)

  @spec build(schema :: %__MODULE__{}, params :: map()) :: Ecto.Changeset.t(t())
  def build(schema \\ %__MODULE__{}, params) do
    schema
    |> Ecto.Changeset.cast(params, [:flow_id, :label, :initial_markings])
    |> Ecto.Changeset.assoc_constraint(:flow)
    |> Ecto.Changeset.validate_required(:initial_markings)
  end

  @spec to_initial_markings(t()) :: [Marking.t()]
  def to_initial_markings(%__MODULE__{} = enactment) do
    enactment.initial_markings
  end
end
