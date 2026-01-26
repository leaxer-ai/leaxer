defmodule LeaxerCore.HardwareMonitor do
  @moduledoc """
  GenServer for monitoring system hardware metrics (CPU, GPU, RAM, VRAM).
  Broadcasts metrics via PubSub at regular intervals.

  ## Supervision

  - **Restart**: Permanent (always restarted)
  - **Strategy**: Part of main supervision tree with `:one_for_one`
  - **Poll Interval**: 1 second

  ## Failure Modes

  - **System command fails**: Returns 0.0 for that metric, continues polling.
    Commands are wrapped in try/rescue to prevent crashes.
  - **GenServer crash**: Metrics history lost, UI shows gaps. Restarts and
    resumes polling immediately.
  - **GPU not detected**: Returns 0.0 for GPU metrics, attempts AMD fallback.

  ## State Recovery

  Metrics history (60 data points) is lost on restart. The monitor immediately
  begins collecting fresh data. No persistent state is maintained.

  ## Windows Performance

  On Windows, CPU monitoring uses TypePerf (a built-in Windows tool) running as
  a long-lived port that streams CPU readings every second. This provides accurate
  hardware-level CPU usage matching Task Manager. Memory monitoring uses `:memsup`
  from the `:os_mon` application.
  """
  use GenServer

  require Logger

  # 1 second
  @poll_interval 1_000
  # Keep 60 data points (1 minute of history)
  @history_size 60

  defstruct [
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

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def get_history do
    GenServer.call(__MODULE__, :get_history)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule first poll
    Process.send_after(self(), :poll, 100)

    # Start TypePerf port on Windows for accurate CPU monitoring
    typeperf_port = start_typeperf_port()

    state = %{
      stats: %__MODULE__{
        cpu_percent: 0,
        memory_percent: 0,
        memory_used_gb: 0,
        memory_total_gb: 0,
        gpu_percent: 0,
        vram_percent: 0,
        vram_used_gb: 0,
        vram_total_gb: 0,
        gpu_name: nil,
        history: %{
          cpu: [],
          memory: [],
          gpu: [],
          vram: []
        }
      },
      last_cpu_times: nil,
      typeperf_port: typeperf_port,
      latest_cpu_reading: 0.0
    }

    {:ok, state}
  end

  @impl true
  def terminate(_reason, %{typeperf_port: port} = _state) when is_port(port) do
    Port.close(port)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, stats_to_map(state.stats), state}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, state.stats.history, state}
  end

  # Handle TypePerf port output for Windows CPU monitoring
  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{typeperf_port: port} = state)
      when is_port(port) do
    case parse_typeperf_line(line) do
      {:ok, cpu} -> {:noreply, %{state | latest_cpu_reading: cpu}}
      _ -> {:noreply, state}
    end
  end

  # Handle TypePerf port exit
  @impl true
  def handle_info({port, {:exit_status, _status}}, %{typeperf_port: port} = state)
      when is_port(port) do
    # TypePerf exited, try to restart it
    new_port = start_typeperf_port()
    {:noreply, %{state | typeperf_port: new_port}}
  end

  @impl true
  def handle_info(:poll, state) do
    # Schedule next poll
    Process.send_after(self(), :poll, @poll_interval)

    # Gather metrics
    {cpu_percent, new_cpu_times} = get_cpu_usage(state.last_cpu_times, state.latest_cpu_reading)

    {mem_percent, mem_used_gb, mem_total_gb} = get_memory_usage()
    {gpu_percent, vram_percent, vram_used_gb, vram_total_gb, gpu_name} = get_gpu_usage()

    # Update history
    history = state.stats.history

    new_history = %{
      cpu: add_to_history(history.cpu, cpu_percent),
      memory: add_to_history(history.memory, mem_percent),
      gpu: add_to_history(history.gpu, gpu_percent),
      vram: add_to_history(history.vram, vram_percent)
    }

    new_stats = %__MODULE__{
      cpu_percent: cpu_percent,
      memory_percent: mem_percent,
      memory_used_gb: mem_used_gb,
      memory_total_gb: mem_total_gb,
      gpu_percent: gpu_percent,
      vram_percent: vram_percent,
      vram_used_gb: vram_used_gb,
      vram_total_gb: vram_total_gb,
      gpu_name: gpu_name,
      history: new_history
    }

    # Broadcast to PubSub
    Phoenix.PubSub.broadcast(
      LeaxerCore.PubSub,
      "hardware:stats",
      {:hardware_stats, stats_to_map(new_stats)}
    )

    {:noreply,
     %{
       state
       | stats: new_stats,
         last_cpu_times: new_cpu_times
     }}
  end

  # Private functions

  defp add_to_history(list, value) do
    [value | list]
    |> Enum.take(@history_size)
  end

  defp stats_to_map(stats) do
    %{
      cpu_percent: round_to(stats.cpu_percent, 1),
      memory_percent: round_to(stats.memory_percent, 1),
      memory_used_gb: round_to(stats.memory_used_gb, 1),
      memory_total_gb: round_to(stats.memory_total_gb, 1),
      gpu_percent: round_to(stats.gpu_percent, 1),
      vram_percent: round_to(stats.vram_percent, 1),
      vram_used_gb: round_to(stats.vram_used_gb, 1),
      vram_total_gb: round_to(stats.vram_total_gb, 1),
      gpu_name: stats.gpu_name,
      history: %{
        cpu: Enum.reverse(stats.history.cpu),
        memory: Enum.reverse(stats.history.memory),
        gpu: Enum.reverse(stats.history.gpu),
        vram: Enum.reverse(stats.history.vram)
      }
    }
  end

  defp round_to(value, decimals) when is_number(value) do
    Float.round(value * 1.0, decimals)
  end

  defp round_to(_, _), do: 0.0

  # CPU Usage - uses OS-level metrics for actual system CPU usage
  defp get_cpu_usage(last_times, latest_cpu_reading) do
    case :os.type() do
      {:win32, _} -> get_windows_cpu(latest_cpu_reading)
      {:unix, :darwin} -> get_macos_cpu(last_times)
      {:unix, _} -> get_linux_cpu(last_times)
      _ -> {0.0, nil}
    end
  end

  # Windows: Use TypePerf for accurate hardware CPU monitoring.
  # TypePerf runs as a long-lived port and streams CPU readings every second.
  # The latest_cpu_reading is updated asynchronously via handle_info.
  defp get_windows_cpu(latest_cpu_reading) do
    {latest_cpu_reading, nil}
  end

  # Start TypePerf port on Windows for continuous CPU monitoring
  defp start_typeperf_port do
    case :os.type() do
      {:win32, _} ->
        typeperf_path = System.find_executable("typeperf")

        if typeperf_path do
          try do
            Port.open({:spawn_executable, typeperf_path}, [
              :binary,
              :exit_status,
              :use_stdio,
              {:line, 1024},
              args: ["\\Processor(_Total)\\% Processor Time", "-si", "1"]
            ])
          rescue
            _ -> nil
          end
        else
          nil
        end

      _ ->
        nil
    end
  end

  # Parse TypePerf output line to extract CPU percentage
  # TypePerf outputs lines like: "01/25/2026 10:30:45.123","12.345678"
  defp parse_typeperf_line(line) do
    # Skip header lines and empty lines
    cond do
      String.contains?(line, "\\Processor") ->
        :skip

      String.trim(line) == "" ->
        :skip

      true ->
        # Try to extract the numeric value from the last quoted field
        case Regex.run(~r/"([0-9.]+)"$/, line) do
          [_, value_str] ->
            case Float.parse(value_str) do
              {value, _} -> {:ok, value}
              :error -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp get_linux_cpu(last_times) do
    try do
      content = File.read!("/proc/stat")
      [cpu_line | _] = String.split(content, "\n")

      # Parse: cpu user nice system idle iowait irq softirq steal guest guest_nice
      ["cpu" | values] = String.split(cpu_line)
      [user, nice, system, idle, iowait | _rest] = Enum.map(values, &String.to_integer/1)

      total = user + nice + system + idle + iowait
      active = user + nice + system

      case last_times do
        nil ->
          {0.0, {active, total}}

        {last_active, last_total} ->
          delta_active = active - last_active
          delta_total = total - last_total
          percent = if delta_total > 0, do: delta_active / delta_total * 100, else: 0.0
          {percent, {active, total}}
      end
    rescue
      # File.Error: /proc/stat not found, MatchError: unexpected format, ArgumentError: parse error
      File.Error -> {0.0, nil}
      MatchError -> {0.0, nil}
      ArgumentError -> {0.0, nil}
    end
  end

  defp get_macos_cpu(_last_times) do
    try do
      # Use top to get CPU usage on macOS
      {output, 0} = System.cmd("top", ["-l", "1", "-n", "0", "-s", "0"], stderr_to_stdout: true)

      # Find line like "CPU usage: 5.26% user, 10.52% sys, 84.21% idle"
      cpu_line =
        output
        |> String.split("\n")
        |> Enum.find(fn line -> String.contains?(line, "CPU usage:") end)

      case cpu_line do
        nil ->
          {0.0, nil}

        line ->
          # Extract user and sys percentages
          case Regex.run(~r/(\d+\.?\d*)% user.*?(\d+\.?\d*)% sys/, line) do
            [_, user, sys] ->
              percent = parse_float(user) + parse_float(sys)
              {percent, nil}

            _ ->
              {0.0, nil}
          end
      end
    rescue
      # ErlangError: command not found, MatchError: non-zero exit code
      ErlangError -> {0.0, nil}
      MatchError -> {0.0, nil}
    end
  end

  # Memory Usage
  defp get_memory_usage do
    case :os.type() do
      {:win32, _} -> get_windows_memory()
      {:unix, :darwin} -> get_macos_memory()
      {:unix, _} -> get_linux_memory()
      _ -> {0.0, 0.0, 0.0}
    end
  end

  # Windows: Use :memsup from :os_mon for native memory monitoring.
  # This avoids spawning PowerShell and is much more efficient.
  defp get_windows_memory do
    try do
      # :memsup.get_memory_data/0 returns {total_bytes, allocated_bytes, {pid, bytes_in_largest_process}}
      {total_bytes, allocated_bytes, _largest_process} = :memsup.get_memory_data()

      # allocated_bytes is memory used by all processes
      used_bytes = allocated_bytes
      total_gb = total_bytes / 1_073_741_824
      used_gb = used_bytes / 1_073_741_824
      percent = if total_bytes > 0, do: used_bytes / total_bytes * 100, else: 0.0

      {percent, used_gb, total_gb}
    rescue
      # Handle cases where memsup is unavailable
      _ -> {0.0, 0.0, 0.0}
    catch
      # Handle exit signals from memsup
      :exit, _ -> {0.0, 0.0, 0.0}
    end
  end

  defp get_linux_memory do
    try do
      content = File.read!("/proc/meminfo")
      lines = String.split(content, "\n")

      values =
        for line <- lines, into: %{} do
          case Regex.run(~r/^(\w+):\s+(\d+)/, line) do
            [_, key, value] -> {key, String.to_integer(value)}
            _ -> {"", 0}
          end
        end

      total_kb = Map.get(values, "MemTotal", 0)
      available_kb = Map.get(values, "MemAvailable", 0)
      used_kb = total_kb - available_kb
      total_gb = total_kb / 1_048_576
      used_gb = used_kb / 1_048_576
      percent = if total_kb > 0, do: used_kb / total_kb * 100, else: 0
      {percent, used_gb, total_gb}
    rescue
      # File.Error: /proc/meminfo not found, MatchError: unexpected format
      File.Error -> {0.0, 0.0, 0.0}
      MatchError -> {0.0, 0.0, 0.0}
    end
  end

  defp get_macos_memory do
    try do
      {output, 0} = System.cmd("vm_stat", [], stderr_to_stdout: true)

      # Parse vm_stat output
      values =
        output
        |> String.split("\n")
        |> Enum.reduce(%{}, fn line, acc ->
          case Regex.run(~r/^(.+?):\s+(\d+)/, line) do
            [_, key, value] -> Map.put(acc, String.trim(key), String.to_integer(value))
            _ -> acc
          end
        end)

      page_size = 4096
      _pages_free = Map.get(values, "Pages free", 0)
      pages_active = Map.get(values, "Pages active", 0)
      pages_inactive = Map.get(values, "Pages inactive", 0)
      pages_speculative = Map.get(values, "Pages speculative", 0)
      pages_wired = Map.get(values, "Pages wired down", 0)

      # Get total memory via sysctl
      {total_output, 0} = System.cmd("sysctl", ["-n", "hw.memsize"], stderr_to_stdout: true)
      total_bytes = String.trim(total_output) |> String.to_integer()
      total_gb = total_bytes / 1_073_741_824

      used_pages = pages_active + pages_inactive + pages_speculative + pages_wired
      used_bytes = used_pages * page_size
      used_gb = used_bytes / 1_073_741_824
      percent = used_bytes / total_bytes * 100

      {percent, used_gb, total_gb}
    rescue
      # ErlangError: command not found, MatchError: non-zero exit, ArgumentError: parse error
      ErlangError -> {0.0, 0.0, 0.0}
      MatchError -> {0.0, 0.0, 0.0}
      ArgumentError -> {0.0, 0.0, 0.0}
    end
  end

  # GPU Usage (NVIDIA via nvidia-smi)
  defp get_gpu_usage do
    case System.cmd(
           "nvidia-smi",
           [
             "--query-gpu=utilization.gpu,memory.used,memory.total,name",
             "--format=csv,noheader,nounits"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        parse_nvidia_smi(output)

      _ ->
        # Try AMD on Linux
        get_amd_gpu_usage()
    end
  rescue
    # ErlangError: nvidia-smi not found (no NVIDIA GPU)
    ErlangError -> get_amd_gpu_usage()
  end

  defp parse_nvidia_smi(output) do
    case String.split(String.trim(output), ",") |> Enum.map(&String.trim/1) do
      [gpu_util, mem_used, mem_total, name] ->
        gpu_percent = parse_float(gpu_util)
        vram_used_mb = parse_float(mem_used)
        vram_total_mb = parse_float(mem_total)
        vram_used_gb = vram_used_mb / 1024
        vram_total_gb = vram_total_mb / 1024
        vram_percent = if vram_total_mb > 0, do: vram_used_mb / vram_total_mb * 100, else: 0

        {gpu_percent, vram_percent, vram_used_gb, vram_total_gb, name}

      _ ->
        {0.0, 0.0, 0.0, 0.0, nil}
    end
  end

  defp get_amd_gpu_usage do
    # Try rocm-smi for AMD GPUs
    case System.cmd("rocm-smi", ["--showuse", "--showmeminfo", "vram", "--json"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, data} ->
            # Parse AMD ROCm output
            card = Map.get(data, "card0", %{})
            gpu_percent = Map.get(card, "GPU use (%)", 0.0)
            vram_total = Map.get(card, "VRAM Total Memory (B)", 0) / 1_073_741_824
            vram_used = Map.get(card, "VRAM Total Used Memory (B)", 0) / 1_073_741_824
            vram_percent = if vram_total > 0, do: vram_used / vram_total * 100, else: 0
            {gpu_percent, vram_percent, vram_used, vram_total, "AMD GPU"}

          _ ->
            {0.0, 0.0, 0.0, 0.0, nil}
        end

      _ ->
        {0.0, 0.0, 0.0, 0.0, nil}
    end
  rescue
    # ErlangError: rocm-smi not found (no AMD GPU)
    ErlangError -> {0.0, 0.0, 0.0, 0.0, nil}
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {value, _} ->
        value

      :error ->
        case Integer.parse(str) do
          {value, _} -> value * 1.0
          :error -> 0.0
        end
    end
  end
end
