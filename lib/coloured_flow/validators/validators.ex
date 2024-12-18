defmodule ColouredFlow.Validators do
  @moduledoc """
  This module is responsible for validate the flow.
  """

  alias ColouredFlow.Definition.ColouredPetriNet

  alias ColouredFlow.Validators.Definition.ColourSetValidator
  alias ColouredFlow.Validators.Definition.ConstantsValidator
  alias ColouredFlow.Validators.Definition.GuardValidator
  alias ColouredFlow.Validators.Definition.StructureValidator
  alias ColouredFlow.Validators.Definition.UniqueNameValidator
  alias ColouredFlow.Validators.Definition.VariablesValidator

  @spec run(ColouredPetriNet.t()) :: {:ok, ColouredPetriNet.t()} | {:error, Exception.t()}
  def run(%ColouredPetriNet{} = cpnet) do
    with(
      {:ok, cpnet} <- StructureValidator.validate(cpnet),
      {:ok, cpnet} <- UniqueNameValidator.validate(cpnet),
      {:ok, cpnet} <- ColourSetValidator.validate(cpnet),
      {:ok, constants} <- ConstantsValidator.validate(cpnet.constants, cpnet),
      cpnet = %ColouredPetriNet{cpnet | constants: constants},
      {:ok, variables} <- VariablesValidator.validate(cpnet.variables, cpnet)
    ) do
      cpnet = %ColouredPetriNet{cpnet | variables: variables}
      GuardValidator.validate(cpnet)
    end
  end
end
