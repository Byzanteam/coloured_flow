defmodule ColouredFlowDashboardWeb.Views.EnactmentRow do
  @moduledoc """
  Wire-shape of a single enactment row rendered on the `/enactments` list.

  Built either from a `ColouredFlow.Runner.Storage.Schemas.Enactment` row
  (mount-time seed) or from a runtime
  `ColouredFlow.Runner.Enactment` lifecycle event delivered through the
  `cf:enactments` telemetry bridge fan-out.

  Fields:

    * `id` — enactment UUID.
    * `flow_id` — owning flow row id.
    * `flow_name` — denormalised display label resolved at row construction
      and refreshed lazily on lifecycle events. Empty string when the
      backend cannot resolve a flow (e.g. InMemory backend listing a flow
      whose cpnet does not match any seeded module — `FlowCatalogStore`
      surfaces `"(unknown)"` in that case; this view keeps an empty string
      so the page can fall back to the id).
    * `state` — enactment lifecycle state mirror.
    * `inserted_at` / `updated_at` — ISO8601 strings; SPA never sees raw
      `DateTime` structs.
    * `live_workitems` — count of `:enabled` + `:started` workitems for
      this enactment. Read at mount; refreshed by lifecycle events that
      change the row's `state`.
  """

  use Musubi.State

  state do
    field :id, String.t()
    field :flow_id, String.t()
    field :flow_name, String.t()
    field :state, :running | :exception | :terminated
    field :inserted_at, String.t()
    field :updated_at, String.t()
    field :live_workitems, integer()
  end
end
