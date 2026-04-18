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

  typed_schema "enactments", null: false do
    belongs_to :flow, Flow

    field :state, Ecto.Enum,
      values: [:running, :exception, :terminated],
      default: :running,
      typed: [type: state()]

    field :label, :string, typed: [null: true]
    field :initial_markings, {:array, Object}, codec: Codec.Marking, typed: [type: [Marking.t()]]

    field :final_markings, {:array, Object},
      codec: Codec.Marking,
      typed: [type: [Marking.t()], null: true]

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
