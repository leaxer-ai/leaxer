defmodule LeaxerCoreWeb.SystemController do
  @moduledoc """
  REST API controller for system operations.

  Provides endpoints for server management operations like restart and cleanup.
  """
  use LeaxerCoreWeb, :controller

  require Logger

  @doc """
  POST /api/system/restart

  Initiates a graceful restart of the server.
  Sends response first, then restarts after a short delay.
  """
  def restart(conn, _params) do
    # Schedule restart after response is sent
    Task.Supervisor.start_child(LeaxerCore.TaskSupervisor, fn ->
      # Give time for response to be sent
      Process.sleep(500)
      # Restart the Erlang VM
      :init.restart()
    end)

    conn
    |> put_status(:ok)
    |> json(%{
      message: "Server restart initiated",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc """
  POST /api/system/cleanup

  Performs system cleanup:
  - Clears tmp directory contents
  - Cleans up orphaned processes
  - Stops sd-server to free VRAM
  - Triggers cache cleanup
  """
  def cleanup(conn, _params) do
    Logger.info("[SystemController] Starting system cleanup...")

    # 0. Cancel any running job first to avoid stale state
    queue_result =
      try do
        queue_state = LeaxerCore.Queue.get_state()

        if queue_state.current_job_id do
          Logger.info("[SystemController] Cancelling running job #{queue_state.current_job_id}")
          LeaxerCore.Queue.cancel(queue_state.current_job_id)
          # Give time for cancellation to complete
          Process.sleep(200)
          :cancelled
        else
          :no_running_job
        end
      catch
        _ -> :error
      end

    # 1. Stop sd-server synchronously to free VRAM
    # Using sync version ensures server is fully stopped before returning
    sd_server_result =
      try do
        LeaxerCore.Workers.StableDiffusionServer.stop_server_sync()
        Logger.info("[SystemController] Stopped sd-server")
        :ok
      catch
        :exit, {:noproc, _} ->
          Logger.debug("[SystemController] sd-server not running")
          :not_running
      end

    # 2. Clean up orphaned processes
    orphan_result =
      try do
        LeaxerCore.Workers.ProcessTracker.health_check()
        Logger.info("[SystemController] Triggered orphan process cleanup")
        :ok
      catch
        _ -> :error
      end

    # 3. Clean up tmp directory
    tmp_result =
      try do
        LeaxerCore.Paths.cleanup_tmp_dir()
        Logger.info("[SystemController] Cleaned tmp directory")
        :ok
      catch
        _ -> :error
      end

    # 4. Trigger cache cleanup (TmpCleaner)
    cache_result =
      try do
        case LeaxerCore.Cleanup.TmpCleaner.cleanup_now() do
          {:ok, stats} ->
            Logger.info("[SystemController] Cache cleanup: removed #{stats.removed_count} files")
            stats

          {:error, reason} ->
            Logger.warning("[SystemController] Cache cleanup failed: #{inspect(reason)}")
            :error
        end
      catch
        _ -> :error
      end

    # 5. Clear execution state (in case of stale state from aborted jobs)
    LeaxerCore.ExecutionState.complete_execution()
    Logger.info("[SystemController] Cleared execution state")

    conn
    |> put_status(:ok)
    |> json(%{
      message: "System cleanup completed",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      results: %{
        running_job: queue_result,
        sd_server: sd_server_result,
        orphan_cleanup: orphan_result,
        tmp_cleanup: tmp_result,
        cache_cleanup: cache_result
      }
    })
  end
end
