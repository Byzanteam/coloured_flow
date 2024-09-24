defmodule ColouredFlow.Runner.Enactment.Snapshot do
  @moduledoc """
  Snapshot is used to store the marking of an enactment at a certain point in version.
  """

  use TypedStructor

  alias ColouredFlow.Enactment.Marking

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :version, non_neg_integer(), doc: "The snapshot version of the enactment."
    field :markings, [Marking.t()], doc: "The snapshot markings of the enactment."
  end
end
