defmodule ColouredFlow.Validators do
  @moduledoc """
  This module is responsible for validate the flow.
  """

  alias ColouredFlow.Definition.ColouredPetriNet

  alias ColouredFlow.Validators.Definition.ActionValidator
  alias ColouredFlow.Validators.Definition.ArcValidator
  alias ColouredFlow.Validators.Definition.ColourSetValidator
  alias ColouredFlow.Validators.Definition.ConstantsValidator
  alias ColouredFlow.Validators.Definition.GuardValidator
  alias ColouredFlow.Validators.Definition.PlacesValidator
  alias ColouredFlow.Validators.Definition.StructureValidator
  alias ColouredFlow.Validators.Definition.TerminationCriteriaValidator
  alias ColouredFlow.Validators.Definition.UniqueNameValidator
  alias ColouredFlow.Validators.Definition.VariablesValidator

  @spec run(ColouredPetriNet.t()) :: {:ok, ColouredPetriNet.t()} | {:error, Exception.t()}
  def run(%ColouredPetriNet{} = cpnet) do
    # credo:disable-for-next-line Credo.Check.Refactor.RedundantWithClauseResult
    with(
      {:ok, %ColouredPetriNet{} = cpnet} <- StructureValidator.validate(cpnet),
      {:ok, %ColouredPetriNet{} = cpnet} <- UniqueNameValidator.validate(cpnet),
      {:ok, %ColouredPetriNet{} = cpnet} <- ColourSetValidator.validate(cpnet),
      {:ok, %ColouredPetriNet{} = cpnet} <- PlacesValidator.validate(cpnet),
      {:ok, constants} <- ConstantsValidator.validate(cpnet.constants, cpnet),
      cpnet = %{cpnet | constants: constants},
      {:ok, variables} <- VariablesValidator.validate(cpnet.variables, cpnet),
      cpnet = %{cpnet | variables: variables},
      {:ok, %ColouredPetriNet{} = cpnet} <- ArcValidator.validate(cpnet),
      {:ok, %ColouredPetriNet{} = cpnet} <- GuardValidator.validate(cpnet),
      {:ok, %ColouredPetriNet{} = cpnet} <- ActionValidator.validate(cpnet),
      {:ok, %ColouredPetriNet{} = cpnet} <- TerminationCriteriaValidator.validate(cpnet)
    ) do
      {:ok, cpnet}
    end
  end
end
