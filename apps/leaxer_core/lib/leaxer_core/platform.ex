defmodule LeaxerCore.Platform do
  @moduledoc """
  Platform abstraction layer for OS-specific operations.

  Centralizes platform-specific code that was previously duplicated across
  multiple workers and modules. Provides a consistent API for:

  - OS type detection (`:windows`, `:macos`, `:linux`)
  - Process management (kill, check if alive)
  - Executable path handling (`.exe` extension on Windows)
  - Port-based process discovery

  ## Examples

      # Get current OS type
      Platform.os_type()
      #=> :windows

      # Kill a process by PID
      Platform.kill_process(12345)
      #=> {:ok, ""}

      # Add .exe extension on Windows
      Platform.executable_path("sd-server")
      #=> "sd-server.exe"  # on Windows
      #=> "sd-server"      # on Unix

      # Check if a process is running
      Platform.process_alive?(12345)
      #=> true

  """

  require Logger

  @type os_type :: :windows | :macos | :linux

  @doc """
  Returns the current operating system type.

  ## Returns

  - `:windows` - Windows systems
  - `:macos` - macOS (Darwin) systems
  - `:linux` - Linux and other Unix systems

  ## Examples

      iex> LeaxerCore.Platform.os_type()
      :windows  # on Windows
  """
  @spec os_type() :: os_type()
  def os_type do
    case :os.type() do
      {:win32, _} -> :windows
      {:unix, :darwin} -> :macos
      {:unix, _} -> :linux
    end
  end

  @doc """
  Returns `true` if running on Windows.

  ## Examples

      iex> LeaxerCore.Platform.windows?()
      true  # on Windows
  """
  @spec windows?() :: boolean()
  def windows?, do: os_type() == :windows

  @doc """
  Returns `true` if running on macOS.

  ## Examples

      iex> LeaxerCore.Platform.macos?()
      true  # on macOS
  """
  @spec macos?() :: boolean()
  def macos?, do: os_type() == :macos

  @doc """
  Returns `true` if running on Linux.

  ## Examples

      iex> LeaxerCore.Platform.linux?()
      true  # on Linux
  """
  @spec linux?() :: boolean()
  def linux?, do: os_type() == :linux

  @doc """
  Returns `true` if running on any Unix-like system (macOS or Linux).

  ## Examples

      iex> LeaxerCore.Platform.unix?()
      true  # on macOS or Linux
  """
  @spec unix?() :: boolean()
  def unix?, do: os_type() in [:macos, :linux]

  @doc """
  Kills an OS process by PID.

  Uses `taskkill /F /PID` on Windows and `kill -9` on Unix systems.
  The `/F` and `-9` flags ensure the process is forcefully terminated.

  ## Arguments

  - `pid` - The OS process ID to kill (integer or string)

  ## Returns

  - `{:ok, output}` - Process killed successfully
  - `{:error, {output, exit_code}}` - Kill command failed

  ## Examples

      iex> LeaxerCore.Platform.kill_process(12345)
      {:ok, ""}

      iex> LeaxerCore.Platform.kill_process(99999)
      {:error, {"ERROR: The process \"99999\" not found.", 128}}
  """
  @spec kill_process(integer() | String.t()) ::
          {:ok, String.t()} | {:error, {String.t(), integer()}}
  def kill_process(pid) do
    pid_str = to_string(pid)
    Logger.debug("[Platform] Killing process #{pid_str}")

    {output, exit_code} =
      case os_type() do
        :windows ->
          System.cmd("taskkill", ["/F", "/PID", pid_str], stderr_to_stdout: true)

        _ ->
          System.cmd("kill", ["-9", pid_str], stderr_to_stdout: true)
      end

    if exit_code == 0 do
      Logger.debug("[Platform] Process #{pid_str} killed successfully")
      {:ok, output}
    else
      Logger.debug("[Platform] Failed to kill process #{pid_str}: exit_code=#{exit_code}")
      {:error, {output, exit_code}}
    end
  rescue
    e ->
      Logger.error("[Platform] Exception killing process #{pid}: #{inspect(e)}")
      {:error, {inspect(e), 1}}
  end

  @doc """
  Kills an OS process by PID, ignoring errors.

  Convenience wrapper around `kill_process/1` that returns `:ok` regardless
  of whether the kill succeeded. Useful for cleanup code where the process
  may have already exited.

  ## Arguments

  - `pid` - The OS process ID to kill (integer or string)

  ## Returns

  Always returns `:ok`.

  ## Examples

      iex> LeaxerCore.Platform.kill_process!(12345)
      :ok

      iex> LeaxerCore.Platform.kill_process!(99999)  # Process doesn't exist
      :ok
  """
  @spec kill_process!(integer() | String.t()) :: :ok
  def kill_process!(pid) do
    kill_process(pid)
    :ok
  end

  @doc """
  Kills a process tree on Windows, or a single process on Unix.

  On Windows, uses `taskkill /F /T /PID` which kills the process and all
  its child processes. On Unix, uses regular `kill -9` (for tree kill,
  consider using process groups).

  ## Arguments

  - `pid` - The OS process ID to kill (integer or string)

  ## Returns

  - `{:ok, output}` - Process(es) killed successfully
  - `{:error, {output, exit_code}}` - Kill command failed

  ## Examples

      iex> LeaxerCore.Platform.kill_process_tree(12345)
      {:ok, ""}
  """
  @spec kill_process_tree(integer() | String.t()) ::
          {:ok, String.t()} | {:error, {String.t(), integer()}}
  def kill_process_tree(pid) do
    pid_str = to_string(pid)
    Logger.debug("[Platform] Killing process tree #{pid_str}")

    {output, exit_code} =
      case os_type() do
        :windows ->
          System.cmd("taskkill", ["/F", "/T", "/PID", pid_str], stderr_to_stdout: true)

        _ ->
          # On Unix, kill -9 kills only the specified process
          # For tree kill, the caller should use process groups
          System.cmd("kill", ["-9", pid_str], stderr_to_stdout: true)
      end

    if exit_code == 0 do
      {:ok, output}
    else
      {:error, {output, exit_code}}
    end
  rescue
    e ->
      Logger.error("[Platform] Exception killing process tree #{pid}: #{inspect(e)}")
      {:error, {inspect(e), 1}}
  end

  @doc """
  Checks if a process is running by PID.

  On Windows, uses `tasklist /FI "PID eq <pid>"` to check if the process exists.
  On Unix, uses `kill -0` which checks process existence without sending a signal.

  ## Arguments

  - `pid` - The OS process ID to check (integer or string)

  ## Returns

  - `true` - Process is running
  - `false` - Process is not running

  ## Examples

      iex> LeaxerCore.Platform.process_alive?(12345)
      true

      iex> LeaxerCore.Platform.process_alive?(99999)
      false
  """
  @spec process_alive?(integer() | String.t()) :: boolean()
  def process_alive?(pid) do
    pid_str = to_string(pid)

    case os_type() do
      :windows ->
        {output, _} = System.cmd("tasklist", ["/FI", "PID eq #{pid_str}"], stderr_to_stdout: true)
        String.contains?(output, pid_str)

      _ ->
        {_, exit_code} = System.cmd("kill", ["-0", pid_str], stderr_to_stdout: true)
        exit_code == 0
    end
  rescue
    _ -> false
  end

  @doc """
  Adds the `.exe` extension to a path on Windows.

  On Unix systems, returns the path unchanged. Useful for building
  executable paths that need to work cross-platform.

  ## Arguments

  - `base_path` - The base executable path without extension

  ## Returns

  The path with `.exe` appended on Windows, unchanged on Unix.

  ## Examples

      iex> LeaxerCore.Platform.executable_path("sd-server")
      "sd-server.exe"  # on Windows
      "sd-server"      # on Unix
  """
  @spec executable_path(String.t()) :: String.t()
  def executable_path(base_path) do
    if windows?(), do: base_path <> ".exe", else: base_path
  end

  @doc """
  Finds the PID of a process listening on a specific port.

  First checks ProcessTracker's ETS table for fast O(1) lookup of tracked processes.
  Falls back to shell commands (netstat/lsof) for processes not registered with ProcessTracker.

  **Note:** For processes spawned by Leaxer workers (sd-server, llama-cli, etc.), prefer
  using `ProcessTracker.find_by_port/1` directly for guaranteed fast lookups.

  ## Arguments

  - `port` - The TCP port number to check

  ## Returns

  - `{:ok, pid}` - Found a process listening on the port
  - `{:error, :not_found}` - No process listening on the port

  ## Examples

      iex> LeaxerCore.Platform.find_process_on_port(8080)
      {:ok, 12345}

      iex> LeaxerCore.Platform.find_process_on_port(9999)
      {:error, :not_found}
  """
  @spec find_process_on_port(integer()) :: {:ok, integer()} | {:error, :not_found}
  def find_process_on_port(port) do
    # First try fast ETS-based lookup via ProcessTracker
    case LeaxerCore.Workers.ProcessTracker.find_by_port(port) do
      {:ok, os_pid} ->
        {:ok, os_pid}

      {:error, :not_found} ->
        # Fall back to shell commands for untracked processes
        # (e.g., orphans from before ProcessTracker existed, or external processes)
        find_process_on_port_shell(port)
    end
  rescue
    _ -> {:error, :not_found}
  end

  # Shell-based port lookup (slow, fragile - used only as fallback)
  defp find_process_on_port_shell(port) do
    case os_type() do
      :windows ->
        find_process_on_port_windows(port)

      _ ->
        find_process_on_port_unix(port)
    end
  rescue
    _ -> {:error, :not_found}
  end

  @doc """
  Kills any process listening on a specific port.

  Combines `find_process_on_port/1` and `kill_process/1` for convenience.
  Includes a brief delay after killing to allow the port to be released.

  First checks ProcessTracker's ETS table for fast O(1) lookup of tracked processes.
  Falls back to shell commands (netstat/lsof) for untracked processes.

  **Note:** For processes spawned by Leaxer workers (sd-server, etc.), prefer using
  `ProcessTracker.kill_by_port/1` directly for guaranteed fast lookups.

  ## Arguments

  - `port` - The TCP port number to free

  ## Returns

  - `{:ok, pid}` - Found and killed the process
  - `{:error, :not_found}` - No process was listening on the port

  ## Examples

      iex> LeaxerCore.Platform.kill_process_on_port(8080)
      {:ok, 12345}

      iex> LeaxerCore.Platform.kill_process_on_port(9999)
      {:error, :not_found}
  """
  @spec kill_process_on_port(integer()) :: {:ok, integer()} | {:error, :not_found}
  def kill_process_on_port(port) do
    Logger.debug("[Platform] Checking for process on port #{port}")

    case find_process_on_port(port) do
      {:ok, pid} ->
        Logger.warning("[Platform] Found process #{pid} on port #{port}, killing...")
        kill_process!(pid)
        # Give it time to release the port
        Process.sleep(500)
        {:ok, pid}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # Private helpers

  defp find_process_on_port_windows(port) do
    case System.cmd("cmd", ["/c", "netstat -ano | findstr :#{port} | findstr LISTENING"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Regex.run(~r/LISTENING\s+(\d+)/, output) do
          [_, pid_str] -> {:ok, String.to_integer(pid_str)}
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp find_process_on_port_unix(port) do
    case System.cmd("lsof", ["-ti", ":#{port}"], stderr_to_stdout: true) do
      {output, 0} ->
        pid_str = String.trim(output)

        if pid_str != "" do
          {:ok, String.to_integer(pid_str)}
        else
          {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end
end
