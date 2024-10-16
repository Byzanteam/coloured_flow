# defmodule FlowDefinitionHelpers do
#   @moduledoc false
#
#   alias ColouredFlow.Definition.Action
#   alias ColouredFlow.Definition.Arc
#   alias ColouredFlow.Definition.Expression
#   alias ColouredFlow.Definition.Place
#   alias ColouredFlow.Definition.Transition
#   alias ColouredFlow.Definition.Variable
#
#   @spec build_arc!(
#           label: Arc.label(),
#           place: Place.name(),
#           transition: Transition.name(),
#           orientation: Arc.orientation(),
#           expression: binary()
#         ) :: Arc.t()
#   def build_arc!(params) do
#     params = Keyword.validate!(params, [:label, :place, :transition, :orientation, :expression])
#     expr = Expression.build!(params[:expression])
#
#     bindings =
#       case params[:orientation] do
#         :p_to_t -> Arc.build_bindings!(expr)
#         :t_to_p -> []
#       end
#
#     %Arc{
#       label: Keyword.get(params, :label),
#       place: params[:place],
#       transition: params[:transition],
#       orientation: params[:orientation],
#       expression: expr,
#       bindings: bindings
#     }
#   end
#
#   @spec build_transition_arcs!(
#           transition :: Transition.name(),
#           params_list :: [
#             label: Arc.label(),
#             place: Place.name(),
#             transition: Transition.name(),
#             orientation: Arc.orientation(),
#             expression: binary()
#           ]
#         ) :: [Arc.t()]
#   def build_transition_arcs!(transition, params_list) do
#     Enum.map(params_list, fn params ->
#       build_arc!([{:transition, transition} | params])
#     end)
#   end
#
#   @spec build_action!(
#           code: binary(),
#           inputs: [Variable.name()],
#           outputs: [Variable.name()]
#         ) :: Action.t()
#   def build_action!(params) do
#     params =
#       params
#       |> Keyword.validate!([:code, :inputs, :outputs])
#       |> Keyword.update!(:code, &Expression.build!/1)
#
#     struct!(Action, params)
#   end
#
#   @spec build_transition!(
#           name: Transition.name(),
#           guard: binary(),
#           action: Action.t()
#         ) :: Transition.t()
#   def build_transition!(params) do
#     params =
#       params
#       |> Keyword.validate!([:name, :guard, :action])
#       |> Keyword.update(:guard, nil, &Expression.build!/1)
#       |> Keyword.update(:action, nil, &build_action!/1)
#
#     struct!(Transition, params)
#   end
# end
#
# defmodule TrafficLight do
#   def flow do
#     alias ColouredFlow.Definition.ColouredPetriNet
#     alias ColouredFlow.Definition.Place
#     alias ColouredFlow.Definition.Variable
#
#     import ColouredFlow.Notation.Colset
#
#     import FlowDefinitionHelpers
#
#     %ColouredPetriNet{
#       colour_sets: [
#         colset(unit() :: {})
#       ],
#       places:
#         Enum.map(
#           ~w[red_ew green_ew yellow_ew red_ns green_ns yellow_ns safe_ew safe_ns],
#           fn name ->
#             %Place{name: name, colour_set: :unit}
#           end
#         ),
#       transitions:
#         Enum.map(
#           ~w[turn_red_ew turn_green_ew turn_yellow_ew turn_red_ns turn_green_ns turn_yellow_ns],
#           &build_transition!(name: &1)
#         ),
#       arcs:
#         [
#           build_arc!(
#             place: "red_ew",
#             transition: "turn_green_ew",
#             orientation: :p_to_t,
#             expression: "bind {1, u}"
#           ),
#           build_arc!(
#             place: "green_ew",
#             transition: "turn_yellow_ew",
#             orientation: :t_to_p,
#             expression: "{1, u}"
#           ),
#           build_arc!(
#             place: "green_ew",
#             transition: "turn_yellow_ew",
#             orientation: :p_to_t,
#             expression: "bind {1, u}"
#           ),
#           build_arc!(
#             place: "yellow_ew",
#             transition: "turn_yellow_ew",
#             orientation: :t_to_p,
#             expression: "{1, u}"
#           ),
#           build_arc!(
#             place: "yellow_ew",
#             transition: "turn_red_ew",
#             orientation: :p_to_t,
#             expression: "bind {1, u}"
#           ),
#           build_arc!(
#             place: "red_ew",
#             transition: "turn_red_ew",
#             orientation: :t_to_p,
#             expression: "{1, u}"
#           )
#         ] ++
#           [
#             build_arc!(
#               place: "red_ns",
#               transition: "turn_green_ns",
#               orientation: :p_to_t,
#               expression: "bind {1, u}"
#             ),
#             build_arc!(
#               place: "green_ns",
#               transition: "turn_yellow_ns",
#               orientation: :t_to_p,
#               expression: "{1, u}"
#             ),
#             build_arc!(
#               place: "green_ns",
#               transition: "turn_yellow_ns",
#               orientation: :p_to_t,
#               expression: "bind {1, u}"
#             ),
#             build_arc!(
#               place: "yellow_ns",
#               transition: "turn_yellow_ns",
#               orientation: :t_to_p,
#               expression: "{1, u}"
#             ),
#             build_arc!(
#               place: "yellow_ns",
#               transition: "turn_red_ns",
#               orientation: :p_to_t,
#               expression: "bind {1, u}"
#             ),
#             build_arc!(
#               place: "red_ns",
#               transition: "turn_red_ns",
#               orientation: :t_to_p,
#               expression: "{1, u}"
#             )
#           ] ++
#           [
#             build_arc!(
#               place: "safe_ew",
#               transition: "turn_red_ns",
#               orientation: :t_to_p,
#               expression: "{1, u}"
#             ),
#             build_arc!(
#               place: "safe_ew",
#               transition: "turn_green_ew",
#               orientation: :p_to_t,
#               expression: "bind {1, u}"
#             ),
#             build_arc!(
#               place: "safe_ns",
#               transition: "turn_red_ew",
#               orientation: :t_to_p,
#               expression: "{1, u}"
#             ),
#             build_arc!(
#               place: "safe_ns",
#               transition: "turn_green_ns",
#               orientation: :p_to_t,
#               expression: "bind {1, u}"
#             )
#           ],
#       variables: [
#         %Variable{name: :u, colour_set: :unit}
#       ]
#     }
#   end
# end
