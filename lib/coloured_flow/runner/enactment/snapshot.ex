defmodule ColouredFlow.Runner.Enactment.Snapshot do
  @moduledoc """
  Snapshot is used to store the marking of an enactment at a certain point in version.
  """

  use TypedStructor

  alias ColouredFlow.Enactment.Marking

  typed_structor enforce: true do
    field :enactment_id, Ecto.UUID.t()
    field :version, non_neg_integer()
    field :markings, [Marking.t()]
  end
end
