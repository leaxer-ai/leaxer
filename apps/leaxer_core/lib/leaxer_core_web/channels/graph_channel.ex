defmodule LeaxerCoreWeb.GraphChannel do
  @moduledoc """
  WebSocket channel for graph execution.
  Handles run_graph events and broadcasts progress/completion.
  """
  use LeaxerCoreWeb, :channel
  require Logger

  alias LeaxerCore.Graph.Execution
  alias LeaxerCore.Runtime

  @models_dir "/opt/lumex/models"

  @impl true
  def join("graph:main", _payload, socket) do
    Logger.info("Client joined graph:main")

    # Subscribe to generation progress updates from SD worker
    Phoenix.PubSub.subscribe(LeaxerCore.PubSub, "generation:progress")
    Phoenix.PubSub.subscribe(LeaxerCore.PubSub, "generation:complete")
    Phoenix.PubSub.subscribe(LeaxerCore.PubSub, "generation:error")

    # Subscribe to queue updates
    Phoenix.PubSub.subscribe(LeaxerCore.PubSub, "queue:updates")

    # Subscribe to runtime events (execution progress, completion, errors)
    Phoenix.PubSub.subscribe(LeaxerCore.PubSub, "runtime:events")

    # Set socket in queue for broadcasting
    LeaxerCore.Queue.set_socket(socket)

    # Send current execution state if any (for browser refresh recovery)
    send(self(), :send_current_state)

    # Send current queue state
    send(self(), :send_queue_state)

    {:ok, socket}
  end

  # Send current execution state to newly joined client
  def handle_info(:send_current_state, socket) do
    case LeaxerCore.ExecutionState.get_state() do
      nil ->
        # No execution in progress
        :ok

      state ->
        # Send current execution state
        push(socket, "execution_resumed", %{
          is_executing: state.is_executing,
          current_node: state.current_node,
          current_index: state.current_index,
          total_nodes: state.total_nodes,
          step_progress: state.step_progress
        })
    end

    {:noreply, socket}
  end

  # Forward generation progress to the client
  @impl true
  def handle_info(
        %{
          job_id: _,
          node_id: node_id,
          current_step: current_step,
          total_steps: total_steps,
          percentage: percentage,
          phase: phase
        } = progress,
        socket
      ) do
    Logger.info(
      "[GraphChannel] Received #{phase} progress: node_id=#{inspect(node_id)}, step=#{current_step}/#{total_steps}"
    )

    # Update execution state for browser refresh recovery
    LeaxerCore.ExecutionState.set_step_progress(node_id, current_step, total_steps, percentage)

    push(socket, "step_progress", progress)
    {:noreply, socket}
  end

  # Fallback for progress without phase (backwards compatibility)
  def handle_info(
        %{
          job_id: _,
          node_id: node_id,
          current_step: current_step,
          total_steps: total_steps,
          percentage: percentage
        } = progress,
        socket
      ) do
    Logger.info(
      "[GraphChannel] Received step progress: node_id=#{inspect(node_id)}, step=#{current_step}/#{total_steps}"
    )

    LeaxerCore.ExecutionState.set_step_progress(node_id, current_step, total_steps, percentage)
    push(socket, "step_progress", Map.put(progress, :phase, "inference"))
    {:noreply, socket}
  end

  def handle_info(%{job_id: _, path: _, elapsed_ms: _} = completion, socket) do
    # Clear execution state on completion
    LeaxerCore.ExecutionState.complete_execution()

    push(socket, "generation_complete", completion)
    {:noreply, socket}
  end

  def handle_info(%{job_id: _, error: _} = error, socket) do
    # Clear execution state on error
    LeaxerCore.ExecutionState.complete_execution()

    push(socket, "generation_error", error)
    {:noreply, socket}
  end

  # Send current queue state to newly joined client
  def handle_info(:send_queue_state, socket) do
    state = LeaxerCore.Queue.get_state()
    push(socket, "queue_updated", state)
    {:noreply, socket}
  end

  # Handle queue PubSub updates
  def handle_info({:queue_updated, state}, socket) do
    push(socket, "queue_updated", state)
    {:noreply, socket}
  end

  def handle_info({:job_completed, job_id, outputs}, socket) do
    Logger.info("[GraphChannel] Job completed: #{job_id}")
    push(socket, "job_completed", %{job_id: job_id, outputs: outputs})
    {:noreply, socket}
  end

  def handle_info({:job_error, job_id, error}, socket) do
    Logger.info("[GraphChannel] Job error: #{job_id} - #{error}")
    push(socket, "job_error", %{job_id: job_id, error: error})
    {:noreply, socket}
  end

  # Handle runtime PubSub events
  def handle_info({event, payload}, socket)
      when event in [
             "execution_progress",
             "execution_complete",
             "execution_error",
             "node_output"
           ] do
    push(socket, event, payload)
    {:noreply, socket}
  end

  # Handle async file operation result from list_models
  def handle_info({:models_list_result, models}, socket) do
    push(socket, "models_list", %{models: models})
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.debug("[GraphChannel] Unhandled message: #{inspect(msg)}")
    {:noreply, socket}
  end

  @impl true
  def handle_in("run_graph", payload, socket) do
    Logger.info("Received run_graph event")

    # Extract compute backend from payload (default to "cpu" for safety)
    compute_backend = Map.get(payload, "compute_backend", "cpu")
    graph_data = Map.drop(payload, ["compute_backend"])

    case Execution.sort_and_validate(graph_data) do
      {:ok, sorted_layers} ->
        # Start runtime in a separate process
        {:ok, pid} =
          Runtime.start_link(
            graph: graph_data,
            sorted_layers: sorted_layers,
            socket: socket,
            compute_backend: compute_backend
          )

        Runtime.run(pid)

        # Store runtime PID in socket assigns for abort capability
        socket = assign(socket, :runtime_pid, pid)
        {:reply, {:ok, %{status: "started"}}, socket}

      {:error, reason, details} ->
        {:reply, {:error, %{reason: reason, details: details}}, socket}
    end
  end

  @impl true
  def handle_in("abort_execution", _payload, socket) do
    Logger.info("Received abort_execution event")

    # Always try to abort the SD worker (it may be running even if runtime is gone)
    LeaxerCore.Workers.StableDiffusion.abort()

    case socket.assigns[:runtime_pid] do
      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          Runtime.abort(pid)
        end

        # Clear execution state on abort
        LeaxerCore.ExecutionState.complete_execution()
        Phoenix.Channel.broadcast(socket, "execution_aborted", %{})
        socket = assign(socket, :runtime_pid, nil)
        {:reply, {:ok, %{status: "aborted"}}, socket}

      _ ->
        # Even if no runtime, still clear state and notify
        LeaxerCore.ExecutionState.complete_execution()
        {:reply, {:ok, %{status: "no_execution"}}, socket}
    end
  end

  @impl true
  def handle_in("list_models", _payload, socket) do
    # Offload file I/O to separate process to avoid blocking channel heartbeat
    # File operations can have significant latency on HDDs or network drives
    channel_pid = self()

    Task.start(fn ->
      local_models =
        case File.ls(@models_dir) do
          {:ok, files} ->
            files
            |> Enum.filter(&File.dir?(Path.join(@models_dir, &1)))
            |> Enum.filter(&(not String.starts_with?(&1, ".")))

          {:error, _} ->
            []
        end

      # Push result back to the channel
      send(channel_pid, {:models_list_result, local_models})
    end)

    # Acknowledge immediately, result comes via push
    {:reply, {:ok, %{status: "loading"}}, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: true}}, socket}
  end

  @impl true
  def handle_in("get_execution_state", _payload, socket) do
    # Manually request execution state (same as auto-sent on join)
    send(self(), :send_current_state)
    {:reply, {:ok, %{status: "sent"}}, socket}
  end

  # Queue management handlers

  @impl true
  def handle_in("queue_jobs", %{"jobs" => jobs}, socket) do
    Logger.info("[GraphChannel] Received queue_jobs with #{length(jobs)} jobs")

    case LeaxerCore.Queue.enqueue(jobs, socket) do
      {:ok, job_ids} ->
        {:reply, {:ok, %{job_ids: job_ids}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("cancel_job", %{"job_id" => job_id}, socket) do
    Logger.info("[GraphChannel] Received cancel_job for #{job_id}")

    case LeaxerCore.Queue.cancel(job_id) do
      :ok ->
        {:reply, {:ok, %{status: "cancelled"}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("get_queue", _payload, socket) do
    state = LeaxerCore.Queue.get_state()
    {:reply, {:ok, state}, socket}
  end

  @impl true
  def handle_in("clear_queue", _payload, socket) do
    Logger.info("[GraphChannel] Received clear_queue")
    LeaxerCore.Queue.clear_pending()
    {:reply, {:ok, %{status: "cleared"}}, socket}
  end
end
