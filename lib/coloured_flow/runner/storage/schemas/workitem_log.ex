defmodule ColouredFlow.Runner.Storage.Schemas.WorkitemLog do
  @moduledoc """
  The schema for the workitem log in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Runner.Enactment.Workitem, as: ColouredWorkitem
  alias ColouredFlow.Runner.Storage.Schemas.Enactment
  alias ColouredFlow.Runner.Storage.Schemas.Workitem

  typed_structor define_struct: false, enforce: true do
    field :id, Types.id()
    field :workitem_id, Types.id()
    field :workitem, Types.association(Workitem.t())
    field :enactment_id, Types.id()
    field :enactment, Types.association(Enactment.t())
    field :from_state, :initial | ColouredWorkitem.state()
    field :to_state, ColouredWorkitem.state()
    field :action, :produce | ColouredWorkitem.transition_action()

    field :inserted_at, DateTime.t()
  end

  schema "workitem_logs" do
    belongs_to :workitem, Workitem
    belongs_to :enactment, Enactment

    field :from_state, Ecto.Enum, values: [:initial | ColouredWorkitem.__states__()]
    field :to_state, Ecto.Enum, values: ColouredWorkitem.__states__()

    field :action, Ecto.Enum,
      values: [
        :produce | ColouredWorkitem.__transitions__() |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
      ]

    timestamps(updated_at: false)
  end
end
