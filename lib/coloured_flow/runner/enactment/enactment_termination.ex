defmodule ColouredFlow.Runner.Enactment.EnactmentTermination do
  @moduledoc """
  Handles the termination of the enactment.
  """

  alias ColouredFlow.Definition.TerminationCriteria
  alias ColouredFlow.Enactment.Marking
  alias ColouredFlow.Runner.Enactment.Workitem

  @doc """
  Check if the enactment should be terminated.
  It should be terminated when the termination criteria are met.
  """
  @spec check_explicit_termination(
          termination_criteria :: TerminationCriteria.t() | nil,
          markings :: [Marking.t()]
        ) :: {:stop, :explicit} | :cont | {:error, Exception.t()}
  def check_explicit_termination(termination_criteria, markings)
  def check_explicit_termination(nil, markings) when is_list(markings), do: :cont

  def check_explicit_termination(%TerminationCriteria{markings: nil}, markings)
      when is_list(markings),
      do: :cont

  def check_explicit_termination(%TerminationCriteria{markings: markings_criteria}, markings)
      when is_list(markings) do
    markings = Map.new(markings, &{&1.place, &1.tokens})

    case ColouredFlow.Runner.Termination.should_terminate(markings_criteria, markings) do
      {:ok, true} ->
        {:stop, :explicit}

      {:ok, false} ->
        :cont

      {:error, [exception | _rest]} ->
        # only pop the closest exception
        {:error, exception}
    end
  end

  @doc """
  Check if the enactment should be terminated implicitly.
  It should be terminated when there are no more enabled workitems.
  """
  @spec check_implicit_termination([Workitem.t()]) :: {:stop, :implicit} | :cont
  def check_implicit_termination(workitems)
  def check_implicit_termination([]), do: {:stop, :implicit}
  def check_implicit_termination([_workitem | _rest]), do: :cont
end
