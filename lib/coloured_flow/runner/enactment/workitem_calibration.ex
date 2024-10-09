defmodule ColouredFlow.Runner.Enactment.WorkitemCalibration do
  @moduledoc """
  Workitem calibration functions, which are responsible for:
  1. withdraw the non-enabled workitem caused by a `allocate` transition
  2. produce new workitems for the new enabled binding elements after the `complete` transition
  """

  use TypedStructor

  alias ColouredFlow.MultiSet

  alias ColouredFlow.Definition.ColouredPetriNet
  alias ColouredFlow.Definition.Place
  alias ColouredFlow.Enactment.BindingElement
  alias ColouredFlow.Enactment.Marking

  alias ColouredFlow.EnabledBindingElements.Computation

  alias ColouredFlow.Runner.Enactment
  alias ColouredFlow.Runner.Enactment.Workitem

  @typep enactment_state() :: Enactment.state()

  typed_structor enforce: true do
    field :state, enactment_state()
    field :to_withdraw, [Workitem.t()], default: []
    field :to_produce, MultiSet.t(BindingElement.t()), default: []
  end

  @doc """
  Initial calibration on the enactment started just now.
  """
  @spec initial_calibrate(enactment_state(), ColouredPetriNet.t()) :: t()
  def initial_calibrate(%Enactment{} = state, %ColouredPetriNet{} = cpnet) do
    binding_elements =
      cpnet.transitions
      |> Enum.flat_map(fn transition ->
        Computation.list(transition, cpnet, state.markings)
      end)
      |> MultiSet.new()

    %{to_produce: to_produce, to_withdraw: to_withdraw, existings: existings} =
      Enum.reduce(
        state.workitems,
        %{to_produce: binding_elements, to_withdraw: [], existings: %{}},
        fn {workitem_id, %Workitem{} = workitem}, ctx ->
          case MultiSet.pop(ctx.to_produce, workitem.binding_element) do
            {0, _binding_elements} ->
              %{ctx | to_withdraw: [workitem | ctx.to_withdraw]}

            {1, binding_elements} ->
              %{
                ctx
                | to_produce: binding_elements,
                  existings: Map.put(ctx.existings, workitem_id, workitem)
              }
          end
        end
      )

    struct!(
      __MODULE__,
      state: %Enactment{state | workitems: existings},
      to_withdraw: to_withdraw,
      to_produce: to_produce
    )
  end

  @doc """
  Calibrate the workitem after a transition.

  ## Parameters
    * `state` : The enactment struct.
    * `transition` : The transition that caused the calibration. See at `ColouredFlow.Runner.Enactment.Workitem.__transitions__/0`
    * `options` : The transition specefied options. See below options.

  ## Allocate options

    * `workitems`: The **original** workitems (before the transition) that are affected by the `allocate` transition.
  """
  @spec calibrate(enactment_state(), :allocate, workitems: [Workitem.t()]) :: t()
  def calibrate(state, transition, options)

  def calibrate(%Enactment{} = state, :allocate, options)
      when is_list(options) do
    workitems = Keyword.fetch!(options, :workitems)
    to_consume_markings = Enum.flat_map(workitems, & &1.binding_element.to_consume)
    place_tokens = Map.new(state.markings, fn {place, marking} -> {place, marking.tokens} end)
    place_tokens = consume_markings(to_consume_markings, place_tokens)

    {workitems, to_withdraw} =
      Map.split_with(state.workitems, fn
        # only enabled workitems should be re-check enabled
        {_workitem_id, %Workitem{state: :enabled} = workitem} ->
          binding_element_enabled?(workitem.binding_element, place_tokens)

        _other ->
          true
      end)

    struct!(
      __MODULE__,
      state: %Enactment{state | workitems: workitems},
      to_withdraw: Map.values(to_withdraw)
    )
  end

  @spec consume_markings(to_consume_markings :: [Marking.t()], place_tokens) :: place_tokens
        when place_tokens: %{Place.name() => Marking.tokens()}
  defp consume_markings([], place_tokens), do: place_tokens

  defp consume_markings([%Marking{} = to_consume | rest], place_tokens) do
    tokens = Map.fetch!(place_tokens, to_consume.place)
    {:ok, remaining_tokens} = MultiSet.safe_difference(tokens, to_consume.tokens)

    case MultiSet.size(remaining_tokens) do
      0 -> consume_markings(rest, Map.delete(place_tokens, to_consume.place))
      _size -> consume_markings(rest, Map.put(place_tokens, to_consume.place, remaining_tokens))
    end
  end

  @spec binding_element_enabled?(
          BindingElement.t(),
          place_tokens :: %{Place.name() => Marking.tokens()}
        ) :: boolean()
  defp binding_element_enabled?(%BindingElement{} = binding_element, place_tokens) do
    Enum.all?(binding_element.to_consume, fn %Marking{} = marking ->
      case Map.fetch(place_tokens, marking.place) do
        :error -> false
        {:ok, tokens} -> MultiSet.include?(tokens, marking.tokens)
      end
    end)
  end
end
