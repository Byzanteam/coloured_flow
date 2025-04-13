defmodule ColouredFlow.Runner.Storage.Schemas.WorkitemLogTest do
  use ColouredFlow.RepoCase

  import Ecto.Query

  alias ColouredFlow.Runner.Enactment.Workitem, as: ColouredWorkitem
  alias ColouredFlow.Runner.Storage.Default
  alias ColouredFlow.Runner.Storage.Repo
  alias ColouredFlow.Runner.Storage.Schemas.Workitem

  test "workitem transition creates log entry" do
    {[workitem], [coloured_workitem]} = insert_workitems({:enabled, :started}, 1)

    :ok = Default.transition_workitem(coloured_workitem, action: :start)

    log =
      Schemas.WorkitemLog
      |> where([l], l.workitem_id == ^coloured_workitem.id)
      |> Repo.one!()

    assert log.workitem_id == workitem.id
    assert log.enactment_id == workitem.enactment_id
    assert log.from_state == :enabled
    assert log.to_state == :started
    assert log.action == :start
  end

  test "batch workitem transition creates log entries" do
    {workitems, coloured_workitems} = insert_workitems({:enabled, :started}, 3)

    :ok = Default.transition_workitems(coloured_workitems, action: :start)

    logs =
      Schemas.WorkitemLog
      |> where([l], l.workitem_id in ^Enum.map(coloured_workitems, & &1.id))
      |> Repo.all()

    assert length(logs) == length(workitems)

    Enum.each(logs, fn log ->
      assert log.from_state == :enabled
      assert log.to_state == :started
      assert log.action == :start
    end)
  end

  for {from_state, action, to_state} <- ColouredWorkitem.__transitions__() do
    test "#{inspect({from_state, action, to_state})} creates log entries" do
      {workitems, coloured_workitems} =
        insert_workitems({unquote(from_state), unquote(to_state)}, 3)

      :ok = Default.transition_workitems(coloured_workitems, action: unquote(action))

      logs =
        Schemas.WorkitemLog
        |> where([l], l.workitem_id in ^Enum.map(coloured_workitems, & &1.id))
        |> Repo.all()

      assert length(logs) == length(workitems)

      Enum.each(logs, fn log ->
        assert log.from_state == unquote(from_state)
        assert log.to_state == unquote(to_state)
        assert log.action == unquote(action)
      end)
    end
  end

  defp insert_workitems({from_state, to_state}, count) do
    workitems = Enum.map(1..count, fn _index -> insert(:workitem, state: from_state) end)

    coloured_workitems =
      Enum.map(workitems, fn workitem ->
        workitem |> Workitem.to_workitem() |> Map.put(:state, to_state)
      end)

    {workitems, coloured_workitems}
  end
end
