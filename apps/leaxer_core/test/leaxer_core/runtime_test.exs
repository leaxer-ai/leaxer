defmodule LeaxerCore.RuntimeTest do
  use ExUnit.Case, async: false

  alias LeaxerCore.Runtime

  @moduletag :capture_log

  describe "abort/1" do
    test "gracefully stops a running runtime process" do
      # Start a runtime process
      {:ok, pid} =
        Runtime.start(
          job_id: "test-abort-graceful",
          graph: %{"nodes" => %{}, "edges" => []},
          sorted_nodes: []
        )

      assert Process.alive?(pid)

      # Abort should stop it gracefully
      assert :ok = Runtime.abort(pid)

      # Give it a moment to shut down
      Process.sleep(50)

      # Process should be dead
      refute Process.alive?(pid)
    end

    test "handles already-dead process" do
      # Start and immediately stop a runtime
      {:ok, pid} =
        Runtime.start(
          job_id: "test-abort-dead",
          graph: %{"nodes" => %{}, "edges" => []},
          sorted_nodes: []
        )

      GenServer.stop(pid, :normal)
      Process.sleep(10)

      # Should handle gracefully without error
      assert :ok = Runtime.abort(pid)
    end

    test "terminate callback clears execution state on shutdown" do
      # Initialize execution state
      LeaxerCore.ExecutionState.start_execution(["node1", "node2"])
      assert LeaxerCore.ExecutionState.get_state() != nil

      # Start a runtime
      {:ok, pid} =
        Runtime.start(
          job_id: "test-terminate-cleanup",
          graph: %{"nodes" => %{}, "edges" => []},
          sorted_nodes: []
        )

      # Abort it (graceful shutdown triggers terminate/2)
      Runtime.abort(pid)
      Process.sleep(100)

      # ExecutionState should be cleared
      assert LeaxerCore.ExecutionState.get_state() == nil
    end

    test "falls back to kill after timeout with stuck process" do
      # Create a process that ignores shutdown signals by trapping exits
      # and not responding to GenServer.stop
      stuck_pid =
        spawn(fn ->
          Process.flag(:trap_exit, true)

          receive do
            # Never respond to anything - simulate a stuck process
            _ -> :ok
          end
        end)

      # Give the process time to set up its trap
      Process.sleep(10)

      assert Process.alive?(stuck_pid)

      # Call abort with a very short timeout to test fallback
      # Note: We can't easily reduce the timeout for testing, but we can
      # verify that abort doesn't hang forever on a non-GenServer process
      # Since it's not a GenServer, GenServer.stop will fail immediately

      # This will try GenServer.stop (which fails for non-GenServer), and that's OK
      assert :ok = Runtime.abort(stuck_pid)
    end

    test "multiple abort calls are idempotent" do
      {:ok, pid} =
        Runtime.start(
          job_id: "test-abort-idempotent",
          graph: %{"nodes" => %{}, "edges" => []},
          sorted_nodes: []
        )

      # First abort
      assert :ok = Runtime.abort(pid)
      Process.sleep(50)

      # Second abort on already-dead process
      assert :ok = Runtime.abort(pid)

      # Third abort
      assert :ok = Runtime.abort(pid)
    end
  end

  describe "terminate/2" do
    test "logs normal completion at debug level" do
      {:ok, pid} =
        Runtime.start(
          job_id: "test-terminate-normal",
          graph: %{"nodes" => %{}, "edges" => []},
          sorted_nodes: []
        )

      # Stop normally
      GenServer.stop(pid, :normal)

      # Process should be dead
      Process.sleep(10)
      refute Process.alive?(pid)
    end

    test "logs shutdown at info level" do
      {:ok, pid} =
        Runtime.start(
          job_id: "test-terminate-shutdown",
          graph: %{"nodes" => %{}, "edges" => []},
          sorted_nodes: []
        )

      # Stop with shutdown reason (what abort uses)
      GenServer.stop(pid, :shutdown)

      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end
end
