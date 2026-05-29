defmodule ColouredFlowDashboard.TelemetryBridge.Event do
  @moduledoc """
  Wire-shape struct broadcast by `ColouredFlowDashboard.TelemetryBridge`.

  Subscribers receive `{:cf_event, %#{inspect(__MODULE__)}{}}` on the topics
  documented at the bridge module.
  """

  use TypedStructor

  @typedoc "UUID identifying an enactment instance — matches `ColouredFlow.Runner.Storage.enactment_id/0`."
  @type enactment_id() :: Ecto.UUID.t()

  @type topic() ::
          :inbox
          | {:enactment, enactment_id()}
          | {:flow, module()}

  @lifecycle_kinds [
    :enactment_start,
    :enactment_stop,
    :enactment_terminate,
    :enactment_exception,
    :enactment_take_snapshot
  ]

  @workitem_op_kinds for op <- [
                           :produce_workitems,
                           :start_workitems,
                           :withdraw_workitems,
                           :complete_workitems
                         ],
                         ev <- [:start, :stop, :exception],
                         do: :"#{op}_#{ev}"

  @type kind() ::
          unquote(ColouredFlow.Types.make_sum_type(@lifecycle_kinds ++ @workitem_op_kinds))

  typed_structor enforce: true do
    plugin TypedStructor.Plugins.DocFields

    field :topic, topic(),
      doc: "Audience the broadcast targets — `:inbox`, `{:enactment, id}`, or `{:flow, mod}`."

    field :kind, kind(),
      doc: "Atom identifying the event family (e.g. `:produce_workitems_stop`)."

    field :enactment_id, enactment_id(),
      doc: "UUID of the enactment that emitted the source telemetry event."

    field :enactment_version, non_neg_integer(),
      doc: "Enactment version *after* the originating runner operation."

    field :occurred_at, DateTime.t(),
      doc: "Server timestamp the event was observed at (DateTime.utc_now/0 fallback)."

    field :payload, map(),
      default: %{},
      enforce: false,
      doc: "Per-kind metadata: workitem_ids, binding_elements, exception_reason, etc."

    field :markings_summary, map(),
      default: %{},
      enforce: false,
      doc: "Lightweight per-place token rollup — never the full Marking structs."

    field :workitems_summary, map(),
      default: %{},
      enforce: false,
      doc: "Live workitem counts grouped by state — never the full Workitem structs."
  end

  @doc "All `kind` atoms the bridge can emit."
  @spec kinds() :: [kind()]
  def kinds, do: unquote(@lifecycle_kinds ++ @workitem_op_kinds)
end
