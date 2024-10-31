defmodule ColouredFlow.Runner.Worklist.WorkitemStreamTest do
  use ColouredFlow.RepoCase, async: true

  alias ColouredFlow.Runner.Worklist.WorkitemStream

  describe "list_live/1" do
    test "works" do
      workitem = insert(:workitem)

      {workitems, cursor} = WorkitemStream.list_live(WorkitemStream.live_query())
      assert [workitem] === preload_assocs(workitems)

      assert :end_of_stream =
               [after_cursor: cursor] |> WorkitemStream.live_query() |> WorkitemStream.list_live()
    end

    test "works with after_cursor" do
      [workitem_1, workitem_2] = insert_pair(:workitem)

      {workitems, cursor} =
        [limit: 1] |> WorkitemStream.live_query() |> WorkitemStream.list_live()

      assert [workitem_1] === preload_assocs(workitems)

      {workitems, cursor} =
        [limit: 1, after_cursor: cursor]
        |> WorkitemStream.live_query()
        |> WorkitemStream.list_live()

      assert [workitem_2] === preload_assocs(workitems)

      assert :end_of_stream =
               [limit: 1, after_cursor: cursor]
               |> WorkitemStream.live_query()
               |> WorkitemStream.list_live()
    end

    test "with invalid after_cursor" do
      [workitem_1, workitem_2] = insert_pair(:workitem)

      {workitems, _cursor} =
        [limit: 2, after_cursor: "abc"]
        |> WorkitemStream.live_query()
        |> WorkitemStream.list_live()

      assert [workitem_1, workitem_2] === preload_assocs(workitems)
    end
  end

  defp preload_assocs(workitems) do
    Repo.preload(workitems, enactment: :flow)
  end
end
