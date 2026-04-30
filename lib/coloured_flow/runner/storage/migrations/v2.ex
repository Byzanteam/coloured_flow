defmodule ColouredFlow.Runner.Migrations.V2 do
  @moduledoc false

  use Ecto.Migration

  @prefix "coloured_flow"

  @spec change(prefix: String.t()) :: :ok
  def change(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, @prefix)
    index_options = [prefix: prefix]

    # Drop indexes that duplicate composite primary keys.
    # `occurrences` PK is `(enactment_id, step_number)` and `snapshots` PK is
    # `enactment_id`; both PKs already provide the same coverage.
    drop index("occurrences", [:enactment_id, :step_number], index_options)
    drop index("snapshots", [:enactment_id], index_options)

    # Add a composite `(enactment_id, state)` index covering the
    # `list_live_workitems` query in
    # `ColouredFlow.Runner.Storage.Default.list_live_workitems/1`. The existing
    # single-column `workitems(state)` index is preserved because
    # `ColouredFlow.Runner.Worklist.WorkitemStream.live_query/1` filters by
    # `state in @live_states` without an `enactment_id` filter, which the
    # composite cannot serve as a left prefix.
    create index("workitems", [:enactment_id, :state], index_options)

    # Cover queries that look up enactments by their parent flow, and support
    # the foreign key reference defined in V0.
    create index("enactments", [:flow_id], index_options)

    # Speed up the `ON DELETE CASCADE` from `workitems` and any future lookup
    # by `workitem_id`. The foreign key is defined in V1.
    create index("workitem_logs", [:workitem_id], index_options)

    :ok
  end
end
