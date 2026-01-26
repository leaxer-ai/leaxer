defmodule LeaxerCore.Queue do
  @moduledoc """
  GenServer managing the job queue. Processes jobs sequentially,
  handles cancellation, and broadcasts state updates via PubSub.

  ## Supervision

  - **Restart**: Permanent (always restarted)
  - **Strategy**: Part of main supervision tree with `:one_for_one`
  - **ETS Table**: `:leaxer_queue` for state persistence

  ## Failure Modes

  - **Queue crash**: Current job fails, ETS state persisted. On restart,
    job list is recovered from ETS but running job is marked as error.
  - **Runtime crash**: Queue receives `:DOWN` message, marks job as error,
    proceeds to next pending job after 100ms delay.
  - **Worker crash**: Worker (StableDiffusion) errors propagate to Runtime,
    which notifies Queue via `{:job_error, job_id, reason}`.

  ## State Recovery

  Job list is persisted to ETS on every state change. On restart:
  - Pending jobs are preserved and will be processed
  - Running job (if any) is marked as `:error` with "Process terminated"
  - Completed/cancelled job history is preserved

  ## Runtime Process Relationship

  Queue spawns Runtime processes using `GenServer.start/1` (not `start_link/1`)
  to avoid being killed when Runtime is aborted. Queue monitors Runtime and
  handles crashes gracefully.

  ## ETS Concurrency Model

  **Table**: `:leaxer_queue`

  **Configuration**: `:set`, `:public`, `:named_table`, `read_concurrency: true`

  ### Access Pattern

  - **Readers**: Not directly used for reads (state accessed via GenServer calls)
  - **Writers**: Queue GenServer on every state change (persistence)

  ### Concurrency Guarantees

  - **Write serialization**: All writes go through the Queue GenServer. State
    mutations are serialized by the GenServer mailbox, ensuring consistent updates.
  - **Persistence safety**: ETS serves as a crash-recovery persistence layer.
    The table is written on every state change via `persist_state/1`.
  - **No concurrent reads**: Unlike other ETS tables, this table is not read
    directly. All state queries go through `get_state/0` which calls the GenServer.

  ### Operations

  | Operation | Access | Frequency | Notes |
  |-----------|--------|-----------|-------|
  | `persist_state/1` | Write | High | On every state change |
  | (GenServer state) | Read | High | State kept in GenServer, not read from ETS |

  ### Persistence Design

  The ETS table stores a single key (`:state`) containing the entire queue state.
  This enables crash recovery: if the GenServer restarts, the supervisor recreates
  the table and the GenServer can restore from the persisted state. The
  `read_concurrency: true` flag has minimal impact since reads bypass ETS.

  ### Recovery Behavior

  On crash, the Queue GenServer is restarted by the supervisor. The ETS table
  is recreated in `init/1`. If a job was running during the crash:

  1. The running job is marked as `:error` with "Process terminated"
  2. Pending jobs are preserved and will be processed
  3. Completed/cancelled history is preserved
  """
  use GenServer
  require Logger

  alias LeaxerCore.Graph.Execution
  alias LeaxerCore.Runtime

  @table_name :leaxer_queue

  # Job status: :pending | :running | :completed | :error | :cancelled
  defmodule Job do
    @moduledoc false
    defstruct [
      :id,
      :workflow_snapshot,
      :status,
      :created_at,
      :started_at,
      :completed_at,
      :error,
      # Cached model path for O(1) sorting (avoids re-traversing workflow on each sort)
      :model_path
    ]
  end

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Add jobs to the queue. Returns {:ok, job_ids} or {:error, reason}"
  def enqueue(workflow_snapshots, socket \\ nil) when is_list(workflow_snapshots) do
    GenServer.call(__MODULE__, {:enqueue, workflow_snapshots, socket})
  end

  @doc "Cancel a job (remove from queue or abort if running)"
  def cancel(job_id) do
    GenServer.call(__MODULE__, {:cancel, job_id})
  end

  @doc "Get current queue state for clients"
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Clear all pending jobs"
  def clear_pending do
    GenServer.call(__MODULE__, :clear_pending)
  end

  @doc "Set the socket for broadcasting (called when channel joins)"
  def set_socket(socket) do
    GenServer.cast(__MODULE__, {:set_socket, socket})
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    # Try to recover from existing ETS table, or create new one
    state =
      case :ets.whereis(@table_name) do
        :undefined ->
          # Create ETS table for state persistence
          :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
          new_state(opts)

        _tid ->
          # Table exists - recover state but mark running jobs as error
          recover_state(opts)
      end

    persist_state(state)
    {:ok, state}
  end

  # Create fresh state
  defp new_state(opts) do
    %{
      jobs: [],
      current_job_id: nil,
      runtime_pid: nil,
      socket: nil,
      batching_enabled: Keyword.get(opts, :batching_enabled, true)
    }
  end

  # Recover state from ETS, marking any running jobs as error
  # (running jobs can't survive a restart since their PIDs are invalid)
  defp recover_state(opts) do
    case :ets.lookup(@table_name, :state) do
      [{:state, persistent}] ->
        # Mark any running jobs as error - they can't be recovered after restart
        recovered_jobs =
          Enum.map(persistent.jobs || [], fn job ->
            if job.status == :running do
              %{
                job
                | status: :error,
                  error: "Process terminated (server restart)",
                  completed_at: System.system_time(:millisecond)
              }
            else
              job
            end
          end)

        Logger.info("[Queue] Recovered #{length(recovered_jobs)} jobs from ETS")

        %{
          jobs: recovered_jobs,
          current_job_id: nil,
          runtime_pid: nil,
          socket: nil,
          batching_enabled:
            Map.get(persistent, :batching_enabled, Keyword.get(opts, :batching_enabled, true))
        }

      [] ->
        new_state(opts)
    end
  end

  @impl true
  def handle_call({:enqueue, workflow_snapshots, socket}, _from, state) do
    # Update socket if provided
    state = if socket, do: %{state | socket: socket}, else: state

    new_jobs =
      Enum.map(workflow_snapshots, fn snapshot ->
        %Job{
          id: generate_job_id(),
          workflow_snapshot: snapshot,
          status: :pending,
          created_at: System.system_time(:millisecond),
          started_at: nil,
          completed_at: nil,
          error: nil,
          # Cache model path at enqueue time to avoid O(N*M) sorting complexity
          model_path: extract_model_path(snapshot)
        }
      end)

    # Add new jobs and optimize order
    all_jobs = state.jobs ++ new_jobs
    optimized_jobs = optimize_job_order(all_jobs, state.batching_enabled, state.current_job_id)

    updated_state = %{state | jobs: optimized_jobs}
    persist_state(updated_state)
    broadcast_queue_update(updated_state)

    # Start processing if not already running
    updated_state = maybe_process_next(updated_state)

    {:reply, {:ok, Enum.map(new_jobs, & &1.id)}, updated_state}
  end

  @impl true
  def handle_call({:cancel, job_id}, _from, state) do
    job = Enum.find(state.jobs, &(&1.id == job_id))

    cond do
      job == nil ->
        {:reply, {:error, :not_found}, state}

      job.status == :running ->
        # Abort the running job
        Logger.info("[Queue] Cancelling running job #{job_id}")

        if state.runtime_pid && Process.alive?(state.runtime_pid) do
          Logger.info("[Queue] Aborting runtime pid #{inspect(state.runtime_pid)}")
          Runtime.abort(state.runtime_pid)
        end

        # Abort both CLI and server mode workers
        LeaxerCore.Workers.StableDiffusion.abort()
        LeaxerCore.Workers.StableDiffusionServer.abort()

        updated_jobs = update_job_status(state.jobs, job_id, :cancelled)

        updated_jobs =
          update_job_field(updated_jobs, job_id, :completed_at, System.system_time(:millisecond))

        updated_state = %{state | jobs: updated_jobs, current_job_id: nil, runtime_pid: nil}
        persist_state(updated_state)
        broadcast_queue_update(updated_state)

        # Clear execution state
        LeaxerCore.ExecutionState.complete_execution()

        # Process next job after a small delay
        Logger.info("[Queue] Scheduling :process_next in 100ms")
        Process.send_after(self(), :process_next, 100)

        {:reply, :ok, updated_state}

      job.status == :pending ->
        # Remove from queue
        updated_jobs = Enum.reject(state.jobs, &(&1.id == job_id))
        updated_state = %{state | jobs: updated_jobs}
        persist_state(updated_state)
        broadcast_queue_update(updated_state)
        {:reply, :ok, updated_state}

      true ->
        # Already completed/error/cancelled
        {:reply, {:error, :invalid_state}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, build_client_state(state), state}
  end

  @impl true
  def handle_call(:clear_pending, _from, state) do
    updated_jobs = Enum.reject(state.jobs, &(&1.status == :pending))
    updated_state = %{state | jobs: updated_jobs}
    persist_state(updated_state)
    broadcast_queue_update(updated_state)
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_cast({:set_socket, socket}, state) do
    {:noreply, %{state | socket: socket}}
  end

  # Handle job completion notification from Runtime (via process message)
  @impl true
  def handle_info({:job_complete, job_id, outputs}, state) do
    # Calculate job duration
    job = Enum.find(state.jobs, &(&1.id == job_id))
    completed_at = System.system_time(:millisecond)
    duration_ms = if job && job.started_at, do: completed_at - job.started_at, else: 0
    duration_str = format_duration(duration_ms)

    Logger.info("[COMPLETE] #{job_id} - job completed in #{duration_str}")

    updated_jobs =
      state.jobs
      |> update_job_status(job_id, :completed)
      |> update_job_field(job_id, :completed_at, completed_at)

    # Re-optimize pending jobs before processing next
    optimized_jobs = optimize_job_order(updated_jobs, state.batching_enabled, nil)

    updated_state = %{state | jobs: optimized_jobs, current_job_id: nil, runtime_pid: nil}
    persist_state(updated_state)
    broadcast_job_completed(updated_state.socket, job_id, outputs)
    broadcast_queue_update(updated_state)

    # Process next job after a small delay
    Process.send_after(self(), :process_next, 100)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:job_error, job_id, error}, state) do
    Logger.error("[Queue] Job #{job_id} failed: #{inspect(error)}")

    updated_jobs =
      state.jobs
      |> update_job_status(job_id, :error)
      |> update_job_field(job_id, :error, format_error(error))
      |> update_job_field(job_id, :completed_at, System.system_time(:millisecond))

    # Re-optimize pending jobs before processing next
    optimized_jobs = optimize_job_order(updated_jobs, state.batching_enabled, nil)

    updated_state = %{state | jobs: optimized_jobs, current_job_id: nil, runtime_pid: nil}
    persist_state(updated_state)
    broadcast_job_error(updated_state.socket, job_id, format_error(error))
    broadcast_queue_update(updated_state)

    # Process next job after a small delay
    Process.send_after(self(), :process_next, 100)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:process_next, state) do
    Logger.info("[Queue] :process_next received, current_job_id=#{inspect(state.current_job_id)}")
    pending_count = Enum.count(state.jobs, &(&1.status == :pending))
    Logger.info("[Queue] Pending jobs: #{pending_count}")
    {:noreply, maybe_process_next(state)}
  end

  # Handle runtime process down (crash or kill)
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    if pid == state.runtime_pid do
      Logger.info("[Queue] Runtime process down: #{inspect(reason)}")

      # Mark job as error if it wasn't already completed/cancelled
      updated_jobs =
        case Enum.find(state.jobs, &(&1.id == state.current_job_id)) do
          %Job{status: :running} = _job ->
            state.jobs
            |> update_job_status(state.current_job_id, :error)
            |> update_job_field(state.current_job_id, :error, "Process terminated")
            |> update_job_field(
              state.current_job_id,
              :completed_at,
              System.system_time(:millisecond)
            )

          _ ->
            state.jobs
        end

      updated_state = %{state | jobs: updated_jobs, current_job_id: nil, runtime_pid: nil}
      persist_state(updated_state)
      broadcast_queue_update(updated_state)

      # Process next job
      Process.send_after(self(), :process_next, 100)

      {:noreply, updated_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Queue] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Private Functions ---

  # Extract model path from workflow snapshot
  defp extract_model_path(workflow_snapshot) do
    nodes = workflow_snapshot["nodes"] || %{}

    # Find LoadModel or GenerateImage nodes
    Enum.find_value(nodes, fn {_id, node} ->
      case node do
        %{"type" => "LoadModel", "data" => data} ->
          data["model_path"]

        %{"type" => "GenerateImage", "data" => data} ->
          case data["model"] do
            %{"path" => path} -> path
            _ -> nil
          end

        _ ->
          nil
      end
    end)
  end

  # Optimize job order by grouping jobs with same model together.
  # Uses cached model_path field for O(N log N) sorting instead of
  # O(N*M) where M is the number of nodes per workflow.
  defp optimize_job_order(jobs, batching_enabled, current_job_id) do
    if not batching_enabled do
      jobs
    else
      # Split into completed/running vs pending
      {finished_or_running, pending} =
        Enum.split_with(jobs, fn job ->
          job.status in [:completed, :error, :cancelled, :running] or
            job.id == current_job_id
        end)

      # Sort pending jobs by cached model path (O(N log N) vs O(N*M))
      sorted_pending = Enum.sort_by(pending, fn job -> job.model_path || "" end)

      # Keep finished/running in original position, then optimized pending jobs
      finished_or_running ++ sorted_pending
    end
  end

  defp maybe_process_next(%{current_job_id: nil} = state) do
    case Enum.find(state.jobs, &(&1.status == :pending)) do
      nil ->
        Logger.info("[Queue] maybe_process_next: no pending jobs")
        state

      job ->
        Logger.info("[Queue] maybe_process_next: starting job #{job.id}")
        start_job(job, state)
    end
  end

  defp maybe_process_next(state) do
    Logger.info(
      "[Queue] maybe_process_next: skipped, current_job_id=#{inspect(state.current_job_id)}"
    )

    state
  end

  defp start_job(job, state) do
    Logger.info("[Queue] Starting job #{job.id}")

    snapshot = job.workflow_snapshot

    case Execution.sort_and_validate(%{
           "nodes" => snapshot["nodes"],
           "edges" => snapshot["edges"]
         }) do
      {:ok, sorted_layers} ->
        # Use start (not start_link) to avoid killing Queue when Runtime is aborted
        {:ok, pid} =
          Runtime.start(
            job_id: job.id,
            graph: %{"nodes" => snapshot["nodes"], "edges" => snapshot["edges"]},
            sorted_layers: sorted_layers,
            socket: state.socket,
            compute_backend: snapshot["compute_backend"] || "cpu",
            model_caching_strategy: snapshot["model_caching_strategy"] || "auto",
            queue_pid: self()
          )

        # Monitor the runtime process for crashes
        Process.monitor(pid)

        Runtime.run(pid)

        updated_jobs =
          state.jobs
          |> update_job_status(job.id, :running)
          |> update_job_field(job.id, :started_at, System.system_time(:millisecond))

        updated_state = %{state | jobs: updated_jobs, current_job_id: job.id, runtime_pid: pid}
        persist_state(updated_state)
        broadcast_queue_update(updated_state)
        updated_state

      {:error, reason, _details} ->
        Logger.error("[Queue] Failed to start job #{job.id}: #{inspect(reason)}")

        updated_jobs =
          state.jobs
          |> update_job_status(job.id, :error)
          |> update_job_field(job.id, :error, format_error(reason))
          |> update_job_field(job.id, :completed_at, System.system_time(:millisecond))

        updated_state = %{state | jobs: updated_jobs}
        persist_state(updated_state)
        broadcast_queue_update(updated_state)

        # Try next job
        maybe_process_next(updated_state)
    end
  end

  defp update_job_status(jobs, job_id, status) do
    Enum.map(jobs, fn job ->
      if job.id == job_id, do: %{job | status: status}, else: job
    end)
  end

  defp update_job_field(jobs, job_id, field, value) do
    Enum.map(jobs, fn job ->
      if job.id == job_id, do: Map.put(job, field, value), else: job
    end)
  end

  defp persist_state(state) do
    # Only persist jobs and config, NEVER PIDs - PIDs become invalid after restart
    # and would cause split-brain issues where we think a process is running when it's not
    persistent = %{
      jobs: state.jobs,
      batching_enabled: state.batching_enabled
    }

    :ets.insert(@table_name, {:state, persistent})
  end

  defp build_client_state(state) do
    # Split jobs by status for efficient client rendering
    {pending_jobs, other_jobs} =
      Enum.split_with(state.jobs, fn job ->
        job.status == :pending
      end)

    running_job = Enum.find(state.jobs, fn job -> job.status == :running end)

    # For history (completed/error/cancelled), only return recent ones
    history_jobs =
      other_jobs
      |> Enum.filter(fn job -> job.status in [:completed, :error, :cancelled] end)
      |> Enum.reverse()
      |> Enum.take(20)
      |> Enum.reverse()

    # Build jobs list: running + pending (limited for display) + history
    display_jobs =
      [
        if(running_job, do: [running_job], else: []),
        # Only send first 10 pending for display
        Enum.take(pending_jobs, 10),
        history_jobs
      ]
      |> List.flatten()

    %{
      jobs: Enum.map(display_jobs, &job_to_map/1),
      is_processing: state.current_job_id != nil,
      current_job_id: state.current_job_id,
      # Include actual counts for UI
      pending_count: length(pending_jobs),
      total_count: length(state.jobs)
    }
  end

  defp job_to_map(%Job{} = job) do
    %{
      id: job.id,
      status: job.status,
      created_at: job.created_at,
      started_at: job.started_at,
      completed_at: job.completed_at,
      error: job.error
    }
  end

  defp broadcast_queue_update(state) do
    Phoenix.PubSub.broadcast(
      LeaxerCore.PubSub,
      "queue:updates",
      {:queue_updated, build_client_state(state)}
    )
  end

  defp broadcast_job_completed(_socket, job_id, outputs) do
    Phoenix.PubSub.broadcast(
      LeaxerCore.PubSub,
      "queue:updates",
      {:job_completed, job_id, outputs}
    )
  end

  defp broadcast_job_error(_socket, job_id, error) do
    Phoenix.PubSub.broadcast(
      LeaxerCore.PubSub,
      "queue:updates",
      {:job_error, job_id, error}
    )
  end

  defp generate_job_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) when ms < 60_000 do
    seconds = Float.round(ms / 1000, 2)
    "#{seconds}s"
  end

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = Float.round(rem(ms, 60_000) / 1000, 1)
    "#{minutes}m #{seconds}s"
  end

  # Format error for storage/display - handles both strings and structured error maps
  defp format_error(error) when is_binary(error), do: error
  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(error) when is_map(error), do: inspect(error)
  defp format_error(error), do: inspect(error)
end
