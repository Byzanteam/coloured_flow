defmodule ColouredFlow.Runner.Enactment.WorkitemCalibration do
  @moduledoc """
  Workitem calibration functions, which are responsible for:
  1. withdraw the non-enabled workitem caused by a `allocate` transition
  2. produce new workitems for the new enabled binding elements after the `complete` transition
  """

  alias ColouredFlow.MultiSet

  alias ColouredFlow.EnabledBindingElements.Computation

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Enactment.Workitem
  alias ColouredFlow.Runner.Storage

  @typep enactment_state() :: Enactment.state()

  @doc """
  Initial calibration on the enactment started just now.
  """
  @spec initial_calibrate(enactment_state()) :: enactment_state()
  def initial_calibrate(%Enactment{} = state) do
    cpnet = Storage.get_flow_by_enactment(state.enactment_id)

    binding_elements =
      cpnet.transitions
      |> Enum.flat_map(fn transition ->
        Computation.list(transition, cpnet, state.markings)
      end)
      |> MultiSet.new()

    %{to_produce: to_produce, to_withdraw: to_withdraw, existings: existings} =
      Enum.reduce(
        state.workitems,
        %{to_produce: binding_elements, to_withdraw: [], existings: []},
        fn %Workitem{} = workitem, ctx ->
          case MultiSet.pop(ctx.to_produce, workitem.binding_element) do
            {0, _binding_elements} ->
              %{ctx | to_withdraw: [workitem | ctx.to_withdraw]}

            {1, binding_elements} ->
              %{ctx | to_produce: binding_elements, existings: [workitem | ctx.existings]}
          end
        end
      )

    produced_workitems = Storage.produce_workitems(state.enactment_id, to_produce)
    _withdrawn = Storage.transition_workitems(to_withdraw, :withdrawn)

    %Enactment{state | workitems: existings ++ produced_workitems}
  end
end
