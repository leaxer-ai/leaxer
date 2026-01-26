defmodule LeaxerCore.PlatformTest do
  use ExUnit.Case, async: true

  alias LeaxerCore.Platform

  describe "os_type/0" do
    test "returns one of the expected OS types" do
      os_type = Platform.os_type()
      assert os_type in [:windows, :macos, :linux]
    end

    test "is consistent with :os.type/0" do
      os_type = Platform.os_type()

      expected =
        case :os.type() do
          {:win32, _} -> :windows
          {:unix, :darwin} -> :macos
          {:unix, _} -> :linux
        end

      assert os_type == expected
    end
  end

  describe "windows?/0" do
    test "returns boolean" do
      assert is_boolean(Platform.windows?())
    end

    test "is consistent with os_type/0" do
      assert Platform.windows?() == (Platform.os_type() == :windows)
    end
  end

  describe "macos?/0" do
    test "returns boolean" do
      assert is_boolean(Platform.macos?())
    end

    test "is consistent with os_type/0" do
      assert Platform.macos?() == (Platform.os_type() == :macos)
    end
  end

  describe "linux?/0" do
    test "returns boolean" do
      assert is_boolean(Platform.linux?())
    end

    test "is consistent with os_type/0" do
      assert Platform.linux?() == (Platform.os_type() == :linux)
    end
  end

  describe "unix?/0" do
    test "returns boolean" do
      assert is_boolean(Platform.unix?())
    end

    test "is true for macOS and Linux, false for Windows" do
      assert Platform.unix?() == Platform.os_type() in [:macos, :linux]
    end

    test "is mutually exclusive with windows?" do
      # One and only one of unix? or windows? should be true
      assert Platform.unix?() != Platform.windows?()
    end
  end

  describe "executable_path/1" do
    test "adds .exe extension on Windows" do
      result = Platform.executable_path("sd-server")

      if Platform.windows?() do
        assert result == "sd-server.exe"
      else
        assert result == "sd-server"
      end
    end

    test "preserves path with directory" do
      result = Platform.executable_path("/path/to/binary")

      if Platform.windows?() do
        assert result == "/path/to/binary.exe"
      else
        assert result == "/path/to/binary"
      end
    end

    test "handles empty string" do
      result = Platform.executable_path("")

      if Platform.windows?() do
        assert result == ".exe"
      else
        assert result == ""
      end
    end
  end

  describe "kill_process/1" do
    test "returns error tuple for non-existent process" do
      # Use a PID that almost certainly doesn't exist
      result = Platform.kill_process(999_999_999)
      assert {:error, {_output, _exit_code}} = result
    end

    test "accepts integer PID" do
      result = Platform.kill_process(999_999_999)
      assert {:error, _} = result
    end

    test "accepts string PID" do
      result = Platform.kill_process("999999999")
      assert {:error, _} = result
    end
  end

  describe "kill_process!/1" do
    test "returns :ok for non-existent process" do
      # Should not raise, just return :ok
      result = Platform.kill_process!(999_999_999)
      assert result == :ok
    end

    test "returns :ok for string PID" do
      result = Platform.kill_process!("999999999")
      assert result == :ok
    end
  end

  describe "kill_process_tree/1" do
    test "returns error tuple for non-existent process" do
      result = Platform.kill_process_tree(999_999_999)
      assert {:error, {_output, _exit_code}} = result
    end
  end

  describe "process_alive?/1" do
    test "returns false for non-existent process" do
      result = Platform.process_alive?(999_999_999)
      assert result == false
    end

    test "returns true for current process (self)" do
      # The current Elixir VM process should be alive
      # Get OS PID of this BEAM process
      os_pid = :os.getpid() |> List.to_integer()
      result = Platform.process_alive?(os_pid)
      assert result == true
    end

    test "accepts string PID" do
      result = Platform.process_alive?("999999999")
      assert result == false
    end
  end

  describe "find_process_on_port/1" do
    test "returns :not_found for unused port" do
      # Use a port that's almost certainly not in use
      result = Platform.find_process_on_port(59_999)
      assert {:error, :not_found} = result
    end
  end

  describe "kill_process_on_port/1" do
    test "returns :not_found when no process on port" do
      result = Platform.kill_process_on_port(59_998)
      assert {:error, :not_found} = result
    end
  end

  describe "integration: spawn and kill process" do
    test "can kill a spawned sleep process" do
      # Spawn a simple sleep process
      {cmd, args} =
        if Platform.windows?() do
          {"cmd", ["/c", "timeout /t 60 /nobreak >nul"]}
        else
          {"sleep", ["60"]}
        end

      port =
        Port.open({:spawn_executable, System.find_executable(cmd)}, [
          :binary,
          :exit_status,
          args: args
        ])

      # Get OS PID
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      # Verify process is alive
      assert Platform.process_alive?(os_pid) == true

      # Kill the process
      result = Platform.kill_process(os_pid)
      assert {:ok, _} = result

      # Wait a bit for process to die
      Process.sleep(100)

      # Verify process is dead
      assert Platform.process_alive?(os_pid) == false

      # Clean up port
      try do
        Port.close(port)
      catch
        :error, _ -> :ok
      end
    end
  end
end
