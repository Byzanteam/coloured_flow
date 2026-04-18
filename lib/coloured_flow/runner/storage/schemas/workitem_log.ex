defmodule ColouredFlow.Runner.Storage.Schemas.WorkitemLog do
  @moduledoc """
  The schema for the workitem log in the coloured_flow runner.
  """

  use ColouredFlow.Runner.Storage.Schemas.Schema

  alias ColouredFlow.Runner.Enactment.Workitem, as: ColouredWorkitem
  alias ColouredFlow.Runner.Storage.Schemas.Enactment
  alias ColouredFlow.Runner.Storage.Schemas.Workitem

  typed_schema "workitem_logs", null: false do
    belongs_to :workitem, Workitem
    belongs_to :enactment, Enactment

    field :from_state, Ecto.Enum,
      values: [:initial | ColouredWorkitem.__states__()],
      typed: [type: :initial | ColouredWorkitem.state()]

    field :to_state, Ecto.Enum,
      values: ColouredWorkitem.__states__(),
      typed: [type: ColouredWorkitem.state()]

    field :action, Ecto.Enum,
      values: [
        :produce | ColouredWorkitem.__transitions__() |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
      ],
      typed: [type: :produce | ColouredWorkitem.transition_action()]

    timestamps(updated_at: false)
  end
end
