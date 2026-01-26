defmodule LeaxerCore.Cleanup.TmpCleaner do
  @moduledoc """
  Periodic cleanup of temporary files in the tmp directory.

  Images generated during workflow execution are stored in the tmp directory.
  Without cleanup, these files accumulate and fill up disk space during long
  running sessions.

  ## Configuration

  Configure via application environment:

      config :leaxer_core, LeaxerCore.Cleanup.TmpCleaner,
        interval_ms: 300_000,      # Check every 5 minutes (default)
        max_age_seconds: 3600,     # Remove files older than 1 hour (default)
        max_size_bytes: 1_073_741_824  # Max 1GB total (default, 0 to disable)

  ## Cleanup Strategy

  Files are removed based on two criteria (checked in order):

  1. **Age-based**: Files older than `max_age_seconds` are always removed
  2. **Size-based**: If total directory size exceeds `max_size_bytes`, oldest
     files are removed until under the limit (disabled if set to 0)

  The tmp directory is also fully cleaned on application startup (see
  `LeaxerCore.Paths.cleanup_tmp_dir/0`).
  """

  use GenServer
  require Logger

  # 5 minutes
  @default_interval_ms 300_000
  # 1 hour
  @default_max_age_seconds 3600
  # 1 GB
  @default_max_size_bytes 1_073_741_824

  # Client API

  @doc """
  Starts the TmpCleaner GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate cleanup. Useful for testing or manual intervention.
  """
  def cleanup_now do
    GenServer.call(__MODULE__, :cleanup_now)
  end

  @doc """
  Returns current statistics about the tmp directory.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    config = Keyword.merge(default_config(), opts)
    interval_ms = Keyword.get(config, :interval_ms)

    # Schedule first cleanup
    schedule_cleanup(interval_ms)

    {:ok, %{config: config}}
  end

  @impl true
  def handle_call(:cleanup_now, _from, state) do
    result = do_cleanup(state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = get_directory_stats()
    {:reply, stats, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    do_cleanup(state.config)

    # Schedule next cleanup
    interval_ms = Keyword.get(state.config, :interval_ms)
    schedule_cleanup(interval_ms)

    {:noreply, state}
  end

  # Private functions

  defp default_config do
    app_config = Application.get_env(:leaxer_core, __MODULE__, [])

    [
      interval_ms: Keyword.get(app_config, :interval_ms, @default_interval_ms),
      max_age_seconds: Keyword.get(app_config, :max_age_seconds, @default_max_age_seconds),
      max_size_bytes: Keyword.get(app_config, :max_size_bytes, @default_max_size_bytes)
    ]
  end

  defp schedule_cleanup(interval_ms) do
    Process.send_after(self(), :cleanup, interval_ms)
  end

  defp do_cleanup(config) do
    tmp_dir = LeaxerCore.Paths.tmp_dir()
    max_age = Keyword.get(config, :max_age_seconds)
    max_size = Keyword.get(config, :max_size_bytes)

    case list_files_with_stats(tmp_dir) do
      {:ok, files} when files != [] ->
        now = System.system_time(:second)
        cutoff_time = now - max_age

        # Phase 1: Remove files older than max_age
        {old_files, recent_files} =
          Enum.split_with(files, fn {_path, stat} ->
            stat.mtime_seconds < cutoff_time
          end)

        old_count = length(old_files)
        old_bytes = Enum.reduce(old_files, 0, fn {_path, stat}, acc -> acc + stat.size end)

        Enum.each(old_files, fn {path, _stat} ->
          File.rm(path)
        end)

        # Phase 2: If size limit enabled and still over, remove oldest first
        {size_count, size_bytes} =
          if max_size > 0 do
            total_size =
              Enum.reduce(recent_files, 0, fn {_path, stat}, acc -> acc + stat.size end)

            cleanup_by_size(recent_files, total_size, max_size)
          else
            {0, 0}
          end

        total_removed = old_count + size_count
        total_bytes = old_bytes + size_bytes

        if total_removed > 0 do
          Logger.info(
            "[TmpCleaner] Removed #{total_removed} files (#{format_bytes(total_bytes)}): " <>
              "#{old_count} expired, #{size_count} for size limit"
          )
        end

        {:ok, %{removed_count: total_removed, removed_bytes: total_bytes}}

      {:ok, []} ->
        {:ok, %{removed_count: 0, removed_bytes: 0}}

      {:error, reason} ->
        Logger.warning("[TmpCleaner] Failed to list tmp directory: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp list_files_with_stats(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        files =
          names
          |> Enum.map(fn name -> Path.join(dir, name) end)
          |> Enum.filter(&File.regular?/1)
          |> Enum.map(fn path ->
            case File.stat(path, time: :posix) do
              {:ok, stat} ->
                {path, %{size: stat.size, mtime_seconds: stat.mtime}}

              {:error, _} ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_by_size(_files, current_size, max_size) when current_size <= max_size do
    {0, 0}
  end

  defp cleanup_by_size(files, current_size, max_size) do
    # Sort by mtime ascending (oldest first)
    sorted = Enum.sort_by(files, fn {_path, stat} -> stat.mtime_seconds end)

    {removed_count, removed_bytes, _} =
      Enum.reduce_while(sorted, {0, 0, current_size}, fn {path, stat}, {count, bytes, size} ->
        if size <= max_size do
          {:halt, {count, bytes, size}}
        else
          File.rm(path)
          {:cont, {count + 1, bytes + stat.size, size - stat.size}}
        end
      end)

    {removed_count, removed_bytes}
  end

  defp get_directory_stats do
    tmp_dir = LeaxerCore.Paths.tmp_dir()

    case list_files_with_stats(tmp_dir) do
      {:ok, files} ->
        total_size = Enum.reduce(files, 0, fn {_path, stat}, acc -> acc + stat.size end)
        file_count = length(files)

        oldest =
          if files == [] do
            nil
          else
            files
            |> Enum.min_by(fn {_path, stat} -> stat.mtime_seconds end)
            |> elem(1)
            |> Map.get(:mtime_seconds)
          end

        %{
          file_count: file_count,
          total_bytes: total_size,
          total_formatted: format_bytes(total_size),
          oldest_mtime: oldest,
          tmp_dir: tmp_dir
        }

      {:error, reason} ->
        %{error: reason}
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
end
