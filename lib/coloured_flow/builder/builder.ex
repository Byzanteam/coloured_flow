defmodule ColouredFlow.Builder do
  @moduledoc """
  This module is responsible for building the flow in a convenient way.
  """

  alias ColouredFlow.Definition.ColouredPetriNet

  alias ColouredFlow.Builder.SetActionOutputs

  @spec build(ColouredPetriNet.t()) :: ColouredPetriNet.t()
  def build(%ColouredPetriNet{} = cpnet) do
    SetActionOutputs.run(cpnet)
  end
end
