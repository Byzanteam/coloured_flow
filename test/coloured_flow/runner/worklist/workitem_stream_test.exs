defmodule ColouredFlow.Runner.Worklist.WorkitemStreamTest do
  use ColouredFlow.RepoCase, async: true

  alias ColouredFlow.Runner.Worklist.WorkitemStream

  describe "list_live/1" do
    test "works" do
      workitem = insert(:workitem)

      {workitems, cursor} = WorkitemStream.list_live()
      assert [Schemas.Workitem.to_workitem(workitem)] === workitems
      assert :end_of_stream = WorkitemStream.list_live(after_cursor: cursor)
    end

    test "works with after_cursor" do
      [workitem_1, workitem_2] = insert_pair(:workitem)

      {workitems, cursor} = WorkitemStream.list_live(limit: 1)
      assert [Schemas.Workitem.to_workitem(workitem_1)] === workitems

      {workitems, cursor} = WorkitemStream.list_live(limit: 1, after_cursor: cursor)
      assert [Schemas.Workitem.to_workitem(workitem_2)] === workitems

      assert :end_of_stream = WorkitemStream.list_live(limit: 1, after_cursor: cursor)
    end

    test "with invalid after_cursor" do
      [workitem_1, workitem_2] = insert_pair(:workitem)

      {workitems, _cursor} = WorkitemStream.list_live(limit: 2, after_cursor: "abc")

      assert Enum.map([workitem_1, workitem_2], &Schemas.Workitem.to_workitem/1) === workitems
    end
  end
end
