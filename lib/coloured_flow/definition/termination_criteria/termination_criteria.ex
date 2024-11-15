defmodule ColouredFlow.Definition.TerminationCriteria do
  @moduledoc """
  Termination criteria for the enactment.
  """
  alias ColouredFlow.Definition.TerminationCriteria.Markings

  use TypedStructor

  typed_structor do
    plugin TypedStructor.Plugins.DocFields

    field :markings, Markings.t(), doc: "The termination criteria applied to place markings."
  end
end
