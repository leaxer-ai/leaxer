defmodule LeaxerCore.HardwareMonitorTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.HardwareMonitor

  @moduletag :capture_log

  describe "get_stats/0" do
    test "returns a map with all expected keys" do
      stats = HardwareMonitor.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :cpu_percent)
      assert Map.has_key?(stats, :memory_percent)
      assert Map.has_key?(stats, :memory_used_gb)
      assert Map.has_key?(stats, :memory_total_gb)
      assert Map.has_key?(stats, :gpu_percent)
      assert Map.has_key?(stats, :vram_percent)
      assert Map.has_key?(stats, :vram_used_gb)
      assert Map.has_key?(stats, :vram_total_gb)
      assert Map.has_key?(stats, :gpu_name)
      assert Map.has_key?(stats, :history)
    end

    test "returns numeric values for percentage fields" do
      stats = HardwareMonitor.get_stats()

      assert is_number(stats.cpu_percent)
      assert is_number(stats.memory_percent)
      assert is_number(stats.gpu_percent)
      assert is_number(stats.vram_percent)
    end

    test "returns numeric values for memory size fields" do
      stats = HardwareMonitor.get_stats()

      assert is_number(stats.memory_used_gb)
      assert is_number(stats.memory_total_gb)
      assert is_number(stats.vram_used_gb)
      assert is_number(stats.vram_total_gb)
    end

    test "percentage values are within valid range" do
      stats = HardwareMonitor.get_stats()

      assert stats.cpu_percent >= 0 and stats.cpu_percent <= 100
      assert stats.memory_percent >= 0 and stats.memory_percent <= 100
      assert stats.gpu_percent >= 0 and stats.gpu_percent <= 100
      assert stats.vram_percent >= 0 and stats.vram_percent <= 100
    end

    test "memory values are non-negative" do
      stats = HardwareMonitor.get_stats()

      assert stats.memory_used_gb >= 0
      assert stats.memory_total_gb >= 0
      assert stats.vram_used_gb >= 0
      assert stats.vram_total_gb >= 0
    end
  end

  describe "get_history/0" do
    test "returns a map with history lists" do
      history = HardwareMonitor.get_history()

      assert is_map(history)
      assert Map.has_key?(history, :cpu)
      assert Map.has_key?(history, :memory)
      assert Map.has_key?(history, :gpu)
      assert Map.has_key?(history, :vram)
    end

    test "history values are lists" do
      history = HardwareMonitor.get_history()

      assert is_list(history.cpu)
      assert is_list(history.memory)
      assert is_list(history.gpu)
      assert is_list(history.vram)
    end
  end

  describe "stats struct" do
    test "struct has all expected fields" do
      struct_keys = Map.keys(%HardwareMonitor{}) -- [:__struct__]

      expected_keys = [
        :cpu_percent,
        :memory_percent,
        :memory_used_gb,
        :memory_total_gb,
        :gpu_percent,
        :vram_percent,
        :vram_used_gb,
        :vram_total_gb,
        :gpu_name,
        :history
      ]

      assert Enum.sort(struct_keys) == Enum.sort(expected_keys)
    end
  end

  describe "performance characteristics" do
    # This test verifies that CPU monitoring doesn't spawn external processes
    # on Windows by checking that the call completes quickly
    test "get_stats completes within reasonable time" do
      # Warm up call
      HardwareMonitor.get_stats()

      # Measure time for 10 consecutive calls
      start_time = System.monotonic_time(:millisecond)

      for _ <- 1..10 do
        HardwareMonitor.get_stats()
      end

      elapsed = System.monotonic_time(:millisecond) - start_time

      # 10 calls should complete in under 500ms
      # If PowerShell was being spawned, this would take several seconds
      assert elapsed < 500,
             "get_stats took #{elapsed}ms for 10 calls, " <>
               "expected < 500ms. This may indicate inefficient process spawning."
    end
  end

  describe "memory monitoring" do
    test "memory_total_gb is greater than zero on a real system" do
      stats = HardwareMonitor.get_stats()

      # Any real system should have at least some memory
      assert stats.memory_total_gb > 0
    end

    test "memory_used_gb is less than or equal to memory_total_gb" do
      stats = HardwareMonitor.get_stats()

      # Used memory should never exceed total
      assert stats.memory_used_gb <= stats.memory_total_gb
    end
  end

  describe "CPU monitoring" do
    test "cpu_percent accumulates after multiple polls" do
      # Wait for a few poll cycles to accumulate data
      Process.sleep(2000)

      stats = HardwareMonitor.get_stats()
      history = HardwareMonitor.get_history()

      # After 2 seconds, we should have at least 1 data point
      assert length(history.cpu) >= 1

      # CPU percent should be a reasonable value
      assert is_number(stats.cpu_percent)
    end
  end
end
