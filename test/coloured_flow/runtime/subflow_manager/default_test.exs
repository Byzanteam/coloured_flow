defmodule ColouredFlow.Runtime.SubFlowManager.DefaultTest do
  use ExUnit.Case, async: true

  alias ColouredFlow.Runtime.SubFlowManager
  alias ColouredFlow.Runtime.SubFlowManager.Default

  describe "new/1" do
    test "creates a new default manager with repo" do
      manager = Default.new(repo: MyApp.Repo)

      assert %Default{repo: MyApp.Repo} = manager
    end

    test "raises when repo is not provided" do
      assert_raise ArgumentError, fn ->
        Default.new([])
      end
    end
  end

  describe "resolve_module/3" do
    test "returns error for invalid module reference format" do
      manager = Default.new(repo: MyApp.Repo)

      # Invalid: not a tuple
      assert {:error, {:invalid_module_ref, _}} =
               SubFlowManager.resolve_module(manager, :invalid, [])

      # Invalid: tuple but wrong format
      assert {:error, {:invalid_module_ref, _}} =
               SubFlowManager.resolve_module(manager, {:wrong_ref, []}, [])
    end

    test "returns error for module_ref with unknown options" do
      manager = Default.new(repo: MyApp.Repo)

      assert {:error, {:invalid_module_ref, _}} =
               SubFlowManager.resolve_module(
                 manager,
                 {:module_ref, unknown_option: "value"},
                 []
               )
    end

    # Note: Full database integration tests would require test database setup
    # and would test:
    # - Loading by flow_id with port_specs
    # - Loading by flow_id with module_name (auto-detect)
    # - Loading by flow_name with port_specs
    # - Loading by flow_name with module_name (auto-detect)
    # - Error handling for non-existent flows
    # - Error handling for conversion failures
  end

  describe "start_child_enactment/4" do
    test "returns not_implemented error" do
      manager = Default.new(repo: MyApp.Repo)

      assert {:error, :not_implemented} =
               SubFlowManager.start_child_enactment(
                 manager,
                 %ColouredFlow.Definition.Module{
                   name: "test_module",
                   port_places: [],
                   places: [],
                   transitions: [],
                   arcs: [],
                   colour_sets: [],
                   variables: [],
                   constants: [],
                   functions: []
                 },
                 [],
                 parent_pid: self()
               )
    end
  end

  describe "get_child_state/2" do
    test "returns not_implemented error" do
      manager = Default.new(repo: MyApp.Repo)

      assert {:error, :not_implemented} =
               SubFlowManager.get_child_state(manager, :some_child_id)
    end
  end
end
