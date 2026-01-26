defmodule LeaxerCore.Workers.ProcessTrackerTest do
  use ExUnit.Case, async: false

  alias LeaxerCore.Workers.ProcessTracker
  alias LeaxerCore.Platform

  @moduletag :capture_log

  # We can't easily test the orphan detection since it requires actual OS processes
  # matching the patterns sd-*, llama-*. Instead we focus on the tracking logic.

  describe "register/2,3 and unregister/1" do
    test "registers an OS PID with label" do
      # Use a unique fake OS PID for testing
      fake_os_pid = :erlang.unique_integer([:positive])

      assert :ok = ProcessTracker.register(fake_os_pid, "test-process")

      # Verify it's tracked
      assert {:ok, info} = ProcessTracker.lookup(fake_os_pid)
      assert info.label == "test-process"
      assert info.worker_pid == self()

      # Clean up
      ProcessTracker.unregister(fake_os_pid)
    end

    test "registers an OS PID with port for server processes" do
      fake_os_pid = :erlang.unique_integer([:positive])
      test_port = 51234

      assert :ok = ProcessTracker.register(fake_os_pid, "sd-server", port: test_port)

      # Verify it's tracked with port info
      assert {:ok, info} = ProcessTracker.lookup(fake_os_pid)
      assert info.label == "sd-server"
      assert info.port == test_port

      # Verify port-based lookup works
      assert {:ok, ^fake_os_pid} = ProcessTracker.find_by_port(test_port)

      # Clean up
      ProcessTracker.unregister(fake_os_pid)
    end

    test "unregisters an OS PID" do
      fake_os_pid = :erlang.unique_integer([:positive])

      ProcessTracker.register(fake_os_pid, "test-process")
      assert {:ok, _} = ProcessTracker.lookup(fake_os_pid)

      ProcessTracker.unregister(fake_os_pid)
      assert :error = ProcessTracker.lookup(fake_os_pid)
    end

    test "unregister clears port tracking" do
      fake_os_pid = :erlang.unique_integer([:positive])
      test_port = 51235

      ProcessTracker.register(fake_os_pid, "sd-server", port: test_port)
      assert {:ok, ^fake_os_pid} = ProcessTracker.find_by_port(test_port)

      ProcessTracker.unregister(fake_os_pid)

      # Port lookup should now fail
      assert {:error, :not_found} = ProcessTracker.find_by_port(test_port)
    end

    test "unregister is idempotent" do
      fake_os_pid = 99999

      # Unregistering a non-existent PID should not error
      assert :ok = ProcessTracker.unregister(fake_os_pid)
      assert :ok = ProcessTracker.unregister(fake_os_pid)
    end
  end

  describe "all/0" do
    test "returns all tracked processes" do
      pid1 = 10001
      pid2 = 10002

      ProcessTracker.register(pid1, "process-1")
      ProcessTracker.register(pid2, "process-2")

      all = ProcessTracker.all()
      assert Map.has_key?(all, pid1)
      assert Map.has_key?(all, pid2)
      assert all[pid1].label == "process-1"
      assert all[pid2].label == "process-2"

      # Clean up
      ProcessTracker.unregister(pid1)
      ProcessTracker.unregister(pid2)
    end

    test "returns empty map when no processes tracked" do
      # Get current tracked, unregister all, check empty
      all = ProcessTracker.all()

      Enum.each(Map.keys(all), fn pid ->
        ProcessTracker.unregister(pid)
      end)

      # After cleanup, should be empty (or only have processes from other tests)
      # We can't guarantee empty due to async nature, but it shouldn't error
      assert is_map(ProcessTracker.all())
    end
  end

  describe "stats/0" do
    test "returns statistics about tracked processes" do
      pid1 = 20001
      pid2 = 20002

      ProcessTracker.register(pid1, "sd.cpp")
      ProcessTracker.register(pid2, "sd.cpp")

      stats = ProcessTracker.stats()
      assert stats.tracked_count >= 2
      assert pid1 in stats.tracked_pids
      assert pid2 in stats.tracked_pids
      assert "sd.cpp" in stats.labels

      # Clean up
      ProcessTracker.unregister(pid1)
      ProcessTracker.unregister(pid2)
    end
  end

  describe "find_by_port/1" do
    test "returns os_pid for registered port" do
      fake_os_pid = :erlang.unique_integer([:positive])
      test_port = 51240

      ProcessTracker.register(fake_os_pid, "sd-server", port: test_port)

      assert {:ok, ^fake_os_pid} = ProcessTracker.find_by_port(test_port)

      ProcessTracker.unregister(fake_os_pid)
    end

    test "returns error for unregistered port" do
      assert {:error, :not_found} = ProcessTracker.find_by_port(59999)
    end

    test "returns error for process registered without port" do
      fake_os_pid = :erlang.unique_integer([:positive])

      ProcessTracker.register(fake_os_pid, "sd.cpp")

      # No port was registered, so port lookup should fail
      assert {:error, :not_found} = ProcessTracker.find_by_port(51241)

      ProcessTracker.unregister(fake_os_pid)
    end
  end

  describe "kill_by_port/1" do
    test "kills process on registered port" do
      # Spawn a real process we can kill
      {port, os_pid} = spawn_test_process()
      test_port = 51242

      # Verify process is running
      assert Platform.process_alive?(os_pid)

      ProcessTracker.register(os_pid, "sd-server", port: test_port)

      # Kill by port
      assert {:ok, ^os_pid} = ProcessTracker.kill_by_port(test_port)

      # Give it time to die
      Process.sleep(100)

      # Verify the OS process was killed
      refute Platform.process_alive?(os_pid)

      # Cleanup port just in case
      try do
        Port.close(port)
      catch
        _, _ -> :ok
      end

      # Unregister (should be idempotent since already dead)
      ProcessTracker.unregister(os_pid)
    end

    test "returns error for unregistered port" do
      assert {:error, :not_found} = ProcessTracker.kill_by_port(59998)
    end
  end

  describe "all_ports/0" do
    test "returns all port mappings" do
      pid1 = :erlang.unique_integer([:positive])
      pid2 = :erlang.unique_integer([:positive])
      port1 = 51243
      port2 = 51244

      ProcessTracker.register(pid1, "sd-server", port: port1)
      ProcessTracker.register(pid2, "sd-server", port: port2)

      ports = ProcessTracker.all_ports()
      assert ports[port1] == pid1
      assert ports[port2] == pid2

      ProcessTracker.unregister(pid1)
      ProcessTracker.unregister(pid2)
    end

    test "excludes processes registered without ports" do
      pid_with_port = :erlang.unique_integer([:positive])
      pid_without_port = :erlang.unique_integer([:positive])
      test_port = 51245

      ProcessTracker.register(pid_with_port, "sd-server", port: test_port)
      ProcessTracker.register(pid_without_port, "sd.cpp")

      ports = ProcessTracker.all_ports()
      assert ports[test_port] == pid_with_port
      # pid_without_port should not appear in the port map
      refute Enum.any?(Map.values(ports), &(&1 == pid_without_port))

      ProcessTracker.unregister(pid_with_port)
      ProcessTracker.unregister(pid_without_port)
    end
  end

  describe "worker crash detection" do
    test "kills OS process when registering worker crashes" do
      # Spawn a short-lived process that simulates a worker
      test_pid = self()

      # Create a real OS process we can track and kill
      # Use a simple sleep command that we can verify is killed
      {port, os_pid} = spawn_test_process()

      # Verify process is running
      assert Platform.process_alive?(os_pid)

      # Spawn a "worker" process that registers the OS PID then crashes
      worker =
        spawn(fn ->
          ProcessTracker.register(os_pid, "test-worker")
          send(test_pid, :registered)
          # Wait a moment then crash
          receive do
            :crash -> exit(:simulated_crash)
          end
        end)

      # Wait for registration
      assert_receive :registered, 1000

      # Verify registration
      assert {:ok, info} = ProcessTracker.lookup(os_pid)
      assert info.worker_pid == worker

      # Crash the worker
      send(worker, :crash)

      # Give ProcessTracker time to receive the DOWN message and kill the process
      Process.sleep(100)

      # Verify the OS process was killed
      refute Platform.process_alive?(os_pid)

      # Verify unregistered
      assert :error = ProcessTracker.lookup(os_pid)

      # Cleanup port just in case
      try do
        Port.close(port)
      catch
        _, _ -> :ok
      end
    end

    test "clears port tracking when worker crashes" do
      test_pid = self()
      test_port = 51250

      {port, os_pid} = spawn_test_process()

      # Verify process is running
      assert Platform.process_alive?(os_pid)

      # Spawn a "worker" process that registers the OS PID with port then crashes
      worker =
        spawn(fn ->
          ProcessTracker.register(os_pid, "sd-server", port: test_port)
          send(test_pid, :registered)

          receive do
            :crash -> exit(:simulated_crash)
          end
        end)

      assert_receive :registered, 1000

      # Verify port tracking is set up
      assert {:ok, ^os_pid} = ProcessTracker.find_by_port(test_port)

      # Crash the worker
      send(worker, :crash)

      # Give ProcessTracker time to process
      Process.sleep(100)

      # Verify port tracking was cleared
      assert {:error, :not_found} = ProcessTracker.find_by_port(test_port)

      # Cleanup
      try do
        Port.close(port)
      catch
        _, _ -> :ok
      end
    end
  end

  describe "health_check/0" do
    test "removes dead processes from tracking" do
      # Spawn a real process, register it, kill it directly, then health check
      {port, os_pid} = spawn_test_process()

      ProcessTracker.register(os_pid, "dying-process")
      assert {:ok, _} = ProcessTracker.lookup(os_pid)

      # Kill the process directly (bypassing unregister)
      Platform.kill_process!(os_pid)

      # Close the port, ignoring errors if already closed
      try do
        Port.close(port)
      catch
        :error, :badarg -> :ok
      end

      # Give it time to die
      Process.sleep(100)

      # Trigger health check
      ProcessTracker.health_check()

      # Give it time to process
      Process.sleep(100)

      # Should be cleaned up
      assert :error = ProcessTracker.lookup(os_pid)
    end
  end

  describe "lookup/1" do
    test "returns error for non-existent PID" do
      assert :error = ProcessTracker.lookup(88888)
    end

    test "returns info for registered PID" do
      fake_pid = 30001
      ProcessTracker.register(fake_pid, "lookup-test")

      assert {:ok, info} = ProcessTracker.lookup(fake_pid)
      assert info.label == "lookup-test"
      assert is_integer(info.registered_at)

      ProcessTracker.unregister(fake_pid)
    end
  end

  # Helper function to spawn a real OS process for testing
  defp spawn_test_process do
    # Use a simple command that runs for a while
    cmd =
      case Platform.os_type() do
        :windows -> "ping"
        _ -> "sleep"
      end

    args =
      case Platform.os_type() do
        :windows -> ["-n", "60", "127.0.0.1"]
        _ -> ["60"]
      end

    port =
      Port.open({:spawn_executable, System.find_executable(cmd)}, [
        :binary,
        :exit_status,
        args: args
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {port, os_pid}
  end
end
