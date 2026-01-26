defmodule LeaxerCore.Workers.ProcessTracker do
  @moduledoc """
  Tracks external OS processes spawned by workers and cleans up orphans.

  Workers like StableDiffusion, LLM, StableDiffusionServer, and Assistant.Server
  spawn external C++ processes (sd.cpp, llama.cpp) via Erlang Ports. If a GenServer
  crashes before properly terminating its Port, the external process becomes orphaned
  and continues consuming resources (especially GPU memory).

  This module provides:

  1. **Process registration** - Workers register their OS PIDs when spawning
  2. **Crash monitoring** - When a worker crashes, associated PIDs are killed
  3. **Startup cleanup** - Find and kill orphaned sd/llama processes on application start
  4. **Periodic health check** - Verify registered PIDs still correspond to running workers
  5. **Port-based lookup** - Find OS PIDs by their listening port (for server processes)

  ## Usage

      # Worker spawns external process and registers it
      {:os_pid, os_pid} = Port.info(port, :os_pid)
      ProcessTracker.register(os_pid, "sd.cpp")

      # Server process with port tracking
      ProcessTracker.register(os_pid, "sd-server", port: 1234)

      # Find/kill process by port (fast - no shell commands)
      ProcessTracker.find_by_port(1234)
      ProcessTracker.kill_by_port(1234)

      # When worker is done (normal exit or cleanup)
      ProcessTracker.unregister(os_pid)

      # On GenServer crash, ProcessTracker receives :DOWN message and kills os_pid

  ## Port Tracking

  Server processes (like sd-server) can be registered with an optional `:port` parameter.
  This enables O(1) lookup of processes by their listening port without shelling out to
  `netstat` (Windows) or `lsof` (Unix), which is fragile, slow, and platform-dependent.

  A secondary ETS table (`:leaxer_port_tracker`) maps ports to OS PIDs for fast lookup.

  ## Startup Cleanup

  On init, the tracker scans for processes matching known patterns (sd-*, llama-*,
  sd-server-*) that aren't tracked by any current worker. These are presumed orphans
  from a previous crash and are terminated.

  ## Periodic Health Check

  Every 60 seconds, the tracker verifies that:
  - All registered OS PIDs are still running
  - Dead PIDs are removed from tracking

  This handles edge cases where a process dies without the tracker being notified.

  ## ETS Concurrency Model

  Uses ETS tables with configuration:

  **`:leaxer_process_tracker`** (primary table):
  - Type: `:set` (unique keys by os_pid)
  - Access: `:public` (for cross-process reads during cleanup)
  - Concurrency: All writes serialized through GenServer

  **`:leaxer_port_tracker`** (secondary index):
  - Type: `:set` (unique keys by port)
  - Access: `:public` (for fast port lookups)
  - Concurrency: All writes serialized through GenServer

  | Operation | Access Type | Frequency | Notes |
  |-----------|-------------|-----------|-------|
  | register/2,3 | write | On worker spawn | Serialized via GenServer |
  | unregister/1 | write | On worker cleanup | Serialized via GenServer |
  | lookup/1 | read | On health check | Direct ETS read |
  | find_by_port/1 | read | On server start | Direct ETS read |
  | all/0 | read | On startup/health | Direct ETS read |
  """

  use GenServer
  require Logger

  alias LeaxerCore.Platform

  @table :leaxer_process_tracker
  @port_table :leaxer_port_tracker
  @health_check_interval 60_000

  # Known process name patterns for orphan detection
  @known_patterns ["sd-", "llama-", "sd-server-"]

  defstruct tracked: %{}

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register an OS process PID for tracking.

  The calling process (worker) is monitored. If the worker crashes, the OS PID
  will be killed automatically.

  ## Parameters

  - `os_pid` - The OS process ID (integer)
  - `label` - Human-readable label for logging (e.g., "sd.cpp", "llama-cli")
  - `opts` - Optional keyword list:
    - `:port` - TCP port the process is listening on (for server processes)

  ## Returns

  - `:ok`

  ## Examples

      # Register a CLI process
      ProcessTracker.register(os_pid, "sd.cpp")

      # Register a server process with port
      ProcessTracker.register(os_pid, "sd-server", port: 1234)
  """
  @spec register(integer(), String.t(), keyword()) :: :ok
  def register(os_pid, label \\ "unknown", opts \\ []) when is_integer(os_pid) do
    port = Keyword.get(opts, :port)
    GenServer.call(__MODULE__, {:register, os_pid, label, port})
  end

  @doc """
  Unregister an OS process PID.

  Call this when the worker has successfully terminated its external process.
  This prevents the tracker from attempting to kill an already-dead process.

  ## Parameters

  - `os_pid` - The OS process ID to unregister

  ## Returns

  - `:ok`
  """
  @spec unregister(integer()) :: :ok
  def unregister(os_pid) when is_integer(os_pid) do
    GenServer.call(__MODULE__, {:unregister, os_pid})
  end

  @doc """
  Get all currently tracked processes.

  Returns a map of `%{os_pid => %{label: label, worker_pid: pid, monitor_ref: ref}}`.
  """
  @spec all() :: map()
  def all do
    case :ets.whereis(@table) do
      :undefined -> %{}
      _tid -> :ets.tab2list(@table) |> Enum.into(%{}, fn {k, v} -> {k, v} end)
    end
  end

  @doc """
  Look up a specific OS PID.

  ## Returns

  - `{:ok, info}` if found
  - `:error` if not found
  """
  @spec lookup(integer()) :: {:ok, map()} | :error
  def lookup(os_pid) do
    case :ets.whereis(@table) do
      :undefined ->
        :error

      _tid ->
        case :ets.lookup(@table, os_pid) do
          [{^os_pid, info}] -> {:ok, info}
          [] -> :error
        end
    end
  end

  @doc """
  Trigger an immediate health check.

  Useful for testing or manual cleanup.
  """
  @spec health_check() :: :ok
  def health_check do
    GenServer.cast(__MODULE__, :health_check)
  end

  @doc """
  Get statistics about tracked processes.
  """
  @spec stats() :: map()
  def stats do
    tracked = all()

    %{
      tracked_count: map_size(tracked),
      tracked_pids: Map.keys(tracked),
      labels: tracked |> Enum.map(fn {_pid, info} -> info.label end) |> Enum.uniq()
    }
  end

  @doc """
  Find the OS PID listening on a specific port.

  This is an O(1) lookup from the ETS table - no shell commands needed.
  Only works for processes registered with the `:port` option.

  ## Parameters

  - `port` - The TCP port number

  ## Returns

  - `{:ok, os_pid}` - Found a tracked process on this port
  - `{:error, :not_found}` - No tracked process on this port

  ## Examples

      iex> ProcessTracker.find_by_port(1234)
      {:ok, 12345}

      iex> ProcessTracker.find_by_port(9999)
      {:error, :not_found}
  """
  @spec find_by_port(integer()) :: {:ok, integer()} | {:error, :not_found}
  def find_by_port(port) when is_integer(port) do
    case :ets.whereis(@port_table) do
      :undefined ->
        {:error, :not_found}

      _tid ->
        case :ets.lookup(@port_table, port) do
          [{^port, os_pid}] -> {:ok, os_pid}
          [] -> {:error, :not_found}
        end
    end
  end

  @doc """
  Kill any tracked process listening on a specific port.

  This is fast because it uses ETS lookup instead of shelling out to
  `netstat` (Windows) or `lsof` (Unix).

  ## Parameters

  - `port` - The TCP port number

  ## Returns

  - `{:ok, os_pid}` - Found and killed the process
  - `{:error, :not_found}` - No tracked process on this port

  ## Examples

      iex> ProcessTracker.kill_by_port(1234)
      {:ok, 12345}

      iex> ProcessTracker.kill_by_port(9999)
      {:error, :not_found}
  """
  @spec kill_by_port(integer()) :: {:ok, integer()} | {:error, :not_found}
  def kill_by_port(port) when is_integer(port) do
    Logger.debug("[ProcessTracker] Looking up process on port #{port}")

    case find_by_port(port) do
      {:ok, os_pid} ->
        Logger.info(
          "[ProcessTracker] Found tracked process #{os_pid} on port #{port}, killing..."
        )

        Platform.kill_process!(os_pid)
        # Give it time to release the port
        Process.sleep(500)
        {:ok, os_pid}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Get all tracked port mappings.

  Returns a map of `%{port => os_pid}`.
  """
  @spec all_ports() :: map()
  def all_ports do
    case :ets.whereis(@port_table) do
      :undefined -> %{}
      _tid -> :ets.tab2list(@port_table) |> Enum.into(%{})
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables for fast lookups
    :ets.new(@table, [:set, :public, :named_table])
    :ets.new(@port_table, [:set, :public, :named_table])

    # Clean up orphaned processes from previous session
    cleanup_orphans()

    # Schedule periodic health check
    schedule_health_check()

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register, os_pid, label, port}, {caller_pid, _tag}, state) do
    port_info = if port, do: " on port #{port}", else: ""

    Logger.debug(
      "[ProcessTracker] Registering OS PID #{os_pid} (#{label}#{port_info}) for #{inspect(caller_pid)}"
    )

    # Monitor the worker process
    ref = Process.monitor(caller_pid)

    info = %{
      label: label,
      worker_pid: caller_pid,
      monitor_ref: ref,
      port: port,
      registered_at: System.monotonic_time(:millisecond)
    }

    # Store in ETS for fast lookups
    :ets.insert(@table, {os_pid, info})

    # Also store port -> os_pid mapping for fast port lookups
    if port do
      :ets.insert(@port_table, {port, os_pid})
    end

    # Also track in GenServer state for monitor ref -> os_pid mapping
    new_tracked = Map.put(state.tracked, ref, os_pid)

    {:reply, :ok, %{state | tracked: new_tracked}}
  end

  def handle_call({:unregister, os_pid}, _from, state) do
    Logger.debug("[ProcessTracker] Unregistering OS PID #{os_pid}")

    case :ets.lookup(@table, os_pid) do
      [{^os_pid, info}] ->
        # Stop monitoring the worker
        Process.demonitor(info.monitor_ref, [:flush])
        # Remove from ETS
        :ets.delete(@table, os_pid)
        # Remove from port table if tracked
        if info[:port] do
          :ets.delete(@port_table, info.port)
        end

        # Remove from state
        new_tracked = Map.delete(state.tracked, info.monitor_ref)
        {:reply, :ok, %{state | tracked: new_tracked}}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast(:health_check, state) do
    do_health_check()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, worker_pid, reason}, state) do
    case Map.get(state.tracked, ref) do
      nil ->
        {:noreply, state}

      os_pid ->
        Logger.warning(
          "[ProcessTracker] Worker #{inspect(worker_pid)} crashed (#{inspect(reason)}), killing OS PID #{os_pid}"
        )

        # Kill the orphaned OS process
        Platform.kill_process!(os_pid)

        # Clean up tracking - get info first to check for port
        case :ets.lookup(@table, os_pid) do
          [{^os_pid, info}] ->
            if info[:port] do
              :ets.delete(@port_table, info.port)
            end

          _ ->
            :ok
        end

        :ets.delete(@table, os_pid)
        new_tracked = Map.delete(state.tracked, ref)

        {:noreply, %{state | tracked: new_tracked}}
    end
  end

  def handle_info(:health_check, state) do
    do_health_check()
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("[ProcessTracker] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp do_health_check do
    tracked = all()

    if map_size(tracked) > 0 do
      Logger.debug("[ProcessTracker] Health check: #{map_size(tracked)} tracked processes")
    end

    # Check each tracked PID is still alive
    Enum.each(tracked, fn {os_pid, info} ->
      unless Platform.process_alive?(os_pid) do
        Logger.info(
          "[ProcessTracker] Tracked PID #{os_pid} (#{info.label}) is no longer running, cleaning up"
        )

        # Process died without us knowing - clean up tracking
        Process.demonitor(info.monitor_ref, [:flush])
        :ets.delete(@table, os_pid)
        # Also clean up port entry if present
        if info[:port] do
          :ets.delete(@port_table, info.port)
        end
      end
    end)
  end

  defp cleanup_orphans do
    Logger.info("[ProcessTracker] Scanning for orphaned processes from previous session...")

    orphans = find_orphaned_processes()

    if Enum.empty?(orphans) do
      Logger.info("[ProcessTracker] No orphaned processes found")
    else
      Logger.warning(
        "[ProcessTracker] Found #{length(orphans)} orphaned process(es), terminating..."
      )

      Enum.each(orphans, fn {os_pid, name} ->
        Logger.info("[ProcessTracker] Killing orphaned process: #{name} (PID #{os_pid})")
        Platform.kill_process!(os_pid)
      end)

      Logger.info("[ProcessTracker] Orphan cleanup complete")
    end
  end

  defp find_orphaned_processes do
    case Platform.os_type() do
      :windows -> find_orphaned_processes_windows()
      _ -> find_orphaned_processes_unix()
    end
  end

  defp find_orphaned_processes_windows do
    # Use tasklist to list processes - more reliable than WMIC on modern Windows
    # We look for sd-*.exe, llama-*.exe patterns
    find_orphaned_processes_windows_tasklist()
  end

  defp find_orphaned_processes_windows_tasklist do
    # Use tasklist to get running processes
    case System.cmd("tasklist", ["/FO", "CSV", "/NH"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.flat_map(fn line ->
          # CSV format: "Image Name","PID","Session Name","Session#","Mem Usage"
          case Regex.run(~r/"([^"]+)","(\d+)"/, line) do
            [_, name, pid_str] ->
              if matches_known_pattern?(name) do
                case Integer.parse(pid_str) do
                  {pid, ""} -> [{pid, name}]
                  _ -> []
                end
              else
                []
              end

            _ ->
              []
          end
        end)

      {_, code} ->
        Logger.debug("[ProcessTracker] tasklist failed with code #{code}")
        []
    end
  rescue
    e ->
      Logger.debug("[ProcessTracker] tasklist exception: #{inspect(e)}")
      []
  end

  defp find_orphaned_processes_unix do
    # Use pgrep or ps to find processes
    # pgrep is more efficient but may not be available everywhere
    case System.cmd("pgrep", ["-f", "sd-|llama-"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.filter(&(&1 != ""))
        |> Enum.flat_map(fn pid_str ->
          case Integer.parse(String.trim(pid_str)) do
            {pid, ""} ->
              # Get process name
              case get_process_name_unix(pid) do
                {:ok, name} -> [{pid, name}]
                :error -> []
              end

            _ ->
              []
          end
        end)

      _ ->
        # pgrep not found or no matches - try ps
        find_orphaned_processes_unix_ps()
    end
  rescue
    e ->
      Logger.warning("[ProcessTracker] Failed to scan for orphans on Unix: #{inspect(e)}")
      []
  end

  defp find_orphaned_processes_unix_ps do
    case System.cmd("ps", ["-eo", "pid,comm"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        # Skip header
        |> Enum.drop(1)
        |> Enum.flat_map(fn line ->
          case String.split(String.trim(line), ~r/\s+/, parts: 2) do
            [pid_str, name] ->
              if matches_known_pattern?(name) do
                case Integer.parse(pid_str) do
                  {pid, ""} -> [{pid, name}]
                  _ -> []
                end
              else
                []
              end

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp get_process_name_unix(pid) do
    case System.cmd("ps", ["-p", to_string(pid), "-o", "comm="], stderr_to_stdout: true) do
      {output, 0} ->
        name = String.trim(output)
        if name != "", do: {:ok, name}, else: :error

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp matches_known_pattern?(name) do
    name_lower = String.downcase(name)
    Enum.any?(@known_patterns, &String.contains?(name_lower, &1))
  end
end
