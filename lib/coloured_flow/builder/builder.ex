defmodule ColouredFlow.Builder do
  @moduledoc """
  This module is responsible for building the flow in a convenient way.
  """

  alias ColouredFlow.Definition.ColouredPetriNet

  alias ColouredFlow.Validators.Definition.ColourSetValidator
  alias ColouredFlow.Validators.Definition.ConstantsValidator
  alias ColouredFlow.Validators.Definition.UniqueNameValidator
  alias ColouredFlow.Validators.Definition.VariablesValidator

  @spec build(ColouredPetriNet.t()) :: {:ok, ColouredPetriNet.t()} | {:error, Exception.t()}
  def build(%ColouredPetriNet{} = cpnet) do
    with(
      {:ok, cpnet} <- UniqueNameValidator.validate(cpnet),
      {:ok, cpnet} <- ColourSetValidator.validate(cpnet),
      {:ok, _constants} <- ConstantsValidator.validate(cpnet.constants, cpnet),
      {:ok, _variables} <- VariablesValidator.validate(cpnet.variables, cpnet)
    ) do
      {:ok, cpnet}
    end
  end
end
