defmodule LeaxerCore.ExecutionStateTest do
  use ExUnit.Case, async: false

  alias LeaxerCore.ExecutionState

  describe "ETS table race condition protection" do
    test "available?/0 returns true when GenServer is running" do
      # The GenServer should be running from the application supervision tree
      assert ExecutionState.available?() == true
    end

    test "get_state/0 returns nil when no execution in progress" do
      # Clear any previous state
      ExecutionState.complete_execution()
      assert ExecutionState.get_state() == nil
    end

    test "get_state/0 returns state when execution in progress" do
      node_ids = ["node_1", "node_2", "node_3"]
      ExecutionState.start_execution(node_ids)

      state = ExecutionState.get_state()
      assert state != nil
      assert state.is_executing == true
      assert state.node_ids == node_ids
      assert state.total_nodes == 3
      assert state.current_node == nil
      assert state.current_index == 0

      # Clean up
      ExecutionState.complete_execution()
    end

    test "set_current_node/3 updates execution state" do
      node_ids = ["node_1", "node_2", "node_3"]
      ExecutionState.start_execution(node_ids)

      ExecutionState.set_current_node("node_2", 1, 3)
      # Give cast time to process
      :timer.sleep(10)

      state = ExecutionState.get_state()
      assert state.current_node == "node_2"
      assert state.current_index == 1
      assert state.step_progress == nil

      # Clean up
      ExecutionState.complete_execution()
    end

    test "set_step_progress/4 updates step progress" do
      node_ids = ["node_1"]
      ExecutionState.start_execution(node_ids)

      ExecutionState.set_step_progress("node_1", 5, 20, 25.0)
      # Give cast time to process
      :timer.sleep(10)

      state = ExecutionState.get_state()
      assert state.current_node == "node_1"

      assert state.step_progress == %{
               current_step: 5,
               total_steps: 20,
               percentage: 25.0
             }

      # Clean up
      ExecutionState.complete_execution()
    end

    test "complete_execution/0 clears state" do
      ExecutionState.start_execution(["node_1"])
      assert ExecutionState.get_state() != nil

      ExecutionState.complete_execution()
      # Give cast time to process
      :timer.sleep(10)

      assert ExecutionState.get_state() == nil
    end

    test "functions return gracefully when ETS table not available" do
      # We can't easily test the race condition directly since the GenServer
      # is already running, but we can verify the defensive code doesn't
      # have syntax errors and the return values are correct types.

      # These should all return :ok without errors even in edge cases
      assert ExecutionState.set_current_node("test", 0, 1) == :ok
      assert ExecutionState.set_step_progress("test", 1, 10, 10.0) == :ok
      assert ExecutionState.complete_execution() == :ok
    end
  end
end
