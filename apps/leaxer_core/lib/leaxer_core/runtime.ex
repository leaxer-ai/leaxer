defmodule LeaxerCore.Runtime do
  @moduledoc """
  GenServer that executes graph nodes in topological order.
  Spawned per job, manages execution context.

  ## Supervision

  - **Restart**: Not supervised directly - spawned by Queue per job
  - **Lifecycle**: Created with `GenServer.start/1`, monitored by Queue
  - **Termination**: Stops normally after job completion or via `abort/1`

  ## Failure Modes

  - **Node execution error**: Logged, execution halts, error reported to Queue.
  - **Node crash (exception)**: Caught in try/rescue, converted to error result.
  - **Runtime crash**: Queue receives `:DOWN` message, marks job as error.
  - **Abort requested**: Two-phase termination: graceful shutdown first (allows
    `terminate/2` to run for cleanup), escalates to `:kill` after 5s timeout.

  ## Process Relationship

  ```
  Queue (permanent)
    └── monitors ──> Runtime (per-job, transient)
                       └── calls ──> Workers (StableDiffusion, LLM, etc.)
  ```

  Runtime is intentionally NOT linked to Queue. Using `GenServer.start/1` instead
  of `start_link/1` ensures Queue survives when Runtime is aborted or crashes.

  ## State

  Holds execution context including:
  - Graph structure (nodes, edges)
  - Execution layers (from scheduler, nodes in each layer can run in parallel)
  - Output accumulator (node outputs keyed by node_id)
  - Progress tracking (current index, total nodes)
  """
  use GenServer
  require Logger

  alias LeaxerCore.Graph.Context
  alias LeaxerCore.Nodes
  alias LeaxerCore.Nodes.Validation
  alias LeaxerCore.Nodes.Error, as: NodeError

  defstruct [
    :job_id,
    :graph,
    :context,
    :socket,
    :sorted_layers,
    :total_nodes,
    :compute_backend,
    :model_caching_strategy,
    :queue_pid
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def run(pid) do
    GenServer.cast(pid, :run)
  end

  @graceful_timeout 5_000

  @doc """
  Abort a running Runtime process.

  Uses a two-phase termination strategy:
  1. First attempts graceful shutdown with `GenServer.stop/3`, allowing
     the `terminate/2` callback to run for cleanup (clearing execution state,
     logging, etc.)
  2. If the process doesn't respond within #{@graceful_timeout}ms, escalates
     to `Process.exit(pid, :kill)` for forceful termination.

  The graceful phase allows:
  - ExecutionState to be cleared (browser refresh recovery)
  - Any open resources to be closed properly
  - Termination to be logged for debugging

  The fallback to `:kill` ensures that even long-running NIFs or stuck
  processes can be stopped, preventing zombie processes.
  """
  def abort(pid) do
    if Process.alive?(pid) do
      # Phase 1: Attempt graceful shutdown
      try do
        GenServer.stop(pid, :shutdown, @graceful_timeout)
      catch
        # Process already dead
        :exit, :noproc ->
          :ok

        # Timeout - process didn't respond to graceful shutdown
        :exit, :timeout ->
          Logger.warning(
            "[Runtime] Graceful shutdown timed out after #{@graceful_timeout}ms, forcing kill"
          )

          if Process.alive?(pid) do
            Process.exit(pid, :kill)
          end

          :ok

        # Other exit reasons (process crashed during stop, etc.)
        :exit, _reason ->
          :ok
      end
    else
      :ok
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    job_id = opts[:job_id] || generate_job_id()

    # Support both new-style layers and old-style flat list (for backward compatibility)
    sorted_layers =
      case {opts[:sorted_layers], opts[:sorted_nodes]} do
        {layers, _} when is_list(layers) and length(layers) > 0 ->
          layers

        {_, nodes} when is_list(nodes) and length(nodes) > 0 ->
          # Check if it's already layers (list of lists) or a flat list of node IDs
          if is_list(hd(nodes)) do
            # Already layers format (from new sort_and_validate)
            nodes
          else
            # Flat list of node IDs (backward compatibility)
            [nodes]
          end

        _ ->
          [[]]
      end

    total_nodes = sorted_layers |> List.flatten() |> length()

    # Get edges from graph for consumer counting (memory GC)
    edges = opts[:graph]["edges"] || []

    state = %__MODULE__{
      job_id: job_id,
      graph: opts[:graph],
      context: Context.new(job_id, edges),
      socket: opts[:socket],
      sorted_layers: sorted_layers,
      total_nodes: total_nodes,
      compute_backend: opts[:compute_backend] || "cpu",
      model_caching_strategy: opts[:model_caching_strategy] || "auto",
      queue_pid: opts[:queue_pid]
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:run, state) do
    Logger.info("Starting execution for job #{state.job_id}")

    # Initialize execution state for browser refresh recovery
    all_nodes = List.flatten(state.sorted_layers)
    LeaxerCore.ExecutionState.start_execution(all_nodes)

    result = execute_nodes(state)

    case result do
      {:ok, final_context} ->
        # Clear execution state on completion
        LeaxerCore.ExecutionState.complete_execution()

        # Filter outputs to remove non-JSON-serializable values (like Nx.Tensor)
        serializable_outputs = sanitize_for_json(final_context.outputs)

        # Notify queue if running as part of queue
        if state.queue_pid do
          send(state.queue_pid, {:job_complete, state.job_id, serializable_outputs})
        else
          # Direct run (legacy) - broadcast directly
          broadcast(state.socket, "execution_complete", %{
            job_id: state.job_id,
            outputs: serializable_outputs
          })
        end

        {:stop, :normal, %{state | context: final_context}}

      {:error, node_id, reason} ->
        # Clear execution state on error
        LeaxerCore.ExecutionState.complete_execution()

        # Notify queue if running as part of queue
        if state.queue_pid do
          send(state.queue_pid, {:job_error, state.job_id, reason})
        else
          # Direct run (legacy) - broadcast directly
          broadcast(state.socket, "execution_error", %{
            job_id: state.job_id,
            node_id: node_id,
            error: reason
          })
        end

        {:stop, :normal, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    # This callback runs when the process is stopped gracefully (via GenServer.stop)
    # or crashes. It does NOT run when killed with Process.exit(pid, :kill).
    #
    # Cleanup responsibilities:
    # 1. Clear execution state (so browser refresh doesn't show stale progress)
    # 2. Log termination for debugging

    # Clear execution state to prevent stale UI state on browser refresh
    LeaxerCore.ExecutionState.complete_execution()

    case reason do
      :normal ->
        Logger.debug("[Runtime] Job #{state.job_id} completed normally")

      :shutdown ->
        Logger.info("[Runtime] Job #{state.job_id} was aborted (graceful shutdown)")

      {:shutdown, _} ->
        Logger.info("[Runtime] Job #{state.job_id} was shut down")

      _ ->
        Logger.warning(
          "[Runtime] Job #{state.job_id} terminated unexpectedly: #{inspect(reason)}"
        )
    end

    :ok
  end

  defp execute_nodes(state) do
    all_nodes = List.flatten(state.sorted_layers)
    Logger.info("Executing #{length(all_nodes)} nodes in #{length(state.sorted_layers)} layers")

    # Execute layers sequentially, but nodes within each layer in parallel
    state.sorted_layers
    |> Enum.reduce_while({:ok, state.context, 0}, fn layer, {:ok, ctx, nodes_completed} ->
      case execute_layer(layer, ctx, state, nodes_completed) do
        {:ok, new_ctx, new_completed} ->
          {:cont, {:ok, new_ctx, new_completed}}

        {:error, node_id, reason} ->
          {:halt, {:error, node_id, reason}}
      end
    end)
    |> case do
      {:ok, final_ctx, _} -> {:ok, final_ctx}
      {:error, node_id, reason} -> {:error, node_id, reason}
    end
  end

  # Execute a single layer - nodes can run in parallel since they have no dependencies
  defp execute_layer([], ctx, _state, nodes_completed), do: {:ok, ctx, nodes_completed}

  defp execute_layer([single_node], ctx, state, nodes_completed) do
    # Single node in layer - execute directly (no parallelism overhead)
    execute_single_node(single_node, ctx, state, nodes_completed + 1)
  end

  defp execute_layer(nodes, ctx, state, nodes_completed) do
    Logger.info("Executing layer with #{length(nodes)} nodes in parallel")

    # Execute nodes in parallel using Task.async_stream
    # Note: we can't update context in parallel since it's immutable,
    # so we collect results and merge them after
    results =
      nodes
      |> Task.async_stream(
        fn node_id ->
          index = nodes_completed + Enum.find_index(nodes, &(&1 == node_id)) + 1
          node = get_in(state.graph, ["nodes", node_id])

          Logger.info(
            "Executing node #{node_id} (#{node["type"]}) - #{index}/#{state.total_nodes}"
          )

          exec_config = %{
            "job_id" => state.job_id,
            "node_id" => node_id,
            "socket" => state.socket,
            "compute_backend" => state.compute_backend,
            "model_caching_strategy" => state.model_caching_strategy
          }

          # Update execution state for browser refresh recovery
          LeaxerCore.ExecutionState.set_current_node(node_id, index, state.total_nodes)

          # Broadcast progress
          broadcast_progress(state, node_id, node["type"], index)

          case execute_node(node, ctx, state.graph, exec_config) do
            {:ok, output, _ctx_after} ->
              Logger.info("Node #{node_id} completed successfully")
              broadcast_node_complete(state, node_id, index)
              broadcast_node_output(state, node_id, output)
              {:ok, node_id, output}

            {:error, reason} ->
              Logger.error("Node #{node_id} failed: #{inspect(reason)}")
              {:error, node_id, reason}
          end
        end,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.to_list()

    # Check for errors and merge successful outputs into context
    errors =
      Enum.filter(results, fn {_status, result} ->
        case result do
          {:error, _, _} -> true
          _ -> false
        end
      end)

    case errors do
      [{:ok, {:error, node_id, reason}} | _] ->
        {:error, node_id, reason}

      [] ->
        # All succeeded - merge outputs into context
        new_ctx =
          Enum.reduce(results, ctx, fn {:ok, {:ok, node_id, output}}, acc_ctx ->
            Context.put_output(acc_ctx, node_id, output)
          end)

        {:ok, new_ctx, nodes_completed + length(nodes)}
    end
  end

  # Execute a single node (used for single-node layers)
  defp execute_single_node(node_id, ctx, state, index) do
    node = get_in(state.graph, ["nodes", node_id])
    ctx = Context.set_current_node(ctx, node_id)

    Logger.info("Executing node #{node_id} (#{node["type"]}) - #{index}/#{state.total_nodes}")

    # Update execution state for browser refresh recovery
    LeaxerCore.ExecutionState.set_current_node(node_id, index, state.total_nodes)

    # Broadcast enhanced progress with graph and node info
    broadcast_progress(state, node_id, node["type"], index)

    # Build execution config with progress context and compute backend
    exec_config = %{
      "job_id" => state.job_id,
      "node_id" => node_id,
      "socket" => state.socket,
      "compute_backend" => state.compute_backend,
      "model_caching_strategy" => state.model_caching_strategy
    }

    case execute_node(node, ctx, state.graph, exec_config) do
      {:ok, output, ctx_after_exec} ->
        Logger.info("Node #{node_id} completed successfully")

        # Broadcast node completion with progress
        broadcast_node_complete(state, node_id, index)

        # Broadcast node output immediately for real-time preview updates
        broadcast_node_output(state, node_id, output)

        new_ctx = Context.put_output(ctx_after_exec, node_id, output)
        {:ok, new_ctx, index}

      {:error, reason} ->
        Logger.error("Node #{node_id} failed: #{inspect(reason)}")
        {:error, node_id, reason}
    end
  end

  # Visual-only node types that should be skipped during execution
  @visual_only_nodes ["Group", "Frame"]

  # Returns {:ok, output, updated_ctx} or {:error, reason}
  # The updated_ctx has consumed inputs for memory GC
  defp execute_node(node, ctx, graph, exec_config) do
    node_type = node["type"]

    node_data = node["data"] || %{}

    cond do
      # Nil type means invalid node
      node_type == nil ->
        {:error, "Node has no type defined"}

      # Skip visual-only nodes
      node_type in @visual_only_nodes ->
        Logger.debug("Skipping visual-only node: #{node_type}")
        {:ok, %{}, ctx}

      # Bypass node - pass data through without processing
      node_data["bypassed"] == true ->
        handle_bypassed_node(node, ctx, graph)

      # Normal execution
      true ->
        module = Nodes.get_module(node_type)

        if module == nil do
          {:error, "Unknown node type: #{node_type}"}
        else
          {inputs, ctx_after_gather} = gather_inputs(node, ctx, graph)
          config_with_exec = Map.merge(node_data, exec_config)

          try do
            # Get input spec for validation
            input_spec = module.input_spec()

            # Run spec-based validation
            with :ok <- Validation.validate_inputs(inputs, node_data, input_spec),
                 # Run custom node validation if implemented
                 :ok <- run_node_validation(module, inputs, config_with_exec) do
              # All validations passed, execute the node
              case module.process(inputs, config_with_exec) do
                {:ok, output} -> {:ok, output, ctx_after_gather}
                {:error, reason} -> {:error, reason}
              end
            else
              {:error, %NodeError{} = error} ->
                error = NodeError.with_context(error, node["id"], node_type)
                Logger.warning("Node #{node["id"]} validation failed: #{error.message}")
                {:error, NodeError.to_map(error)}

              {:error, reason} when is_binary(reason) ->
                Logger.warning("Node #{node["id"]} validation failed: #{reason}")
                {:error, reason}

              {:error, reason} ->
                Logger.warning("Node #{node["id"]} validation failed: #{inspect(reason)}")
                {:error, reason}
            end
          rescue
            e ->
              Logger.error("Node #{node["id"]} crashed: #{Exception.message(e)}")
              {:error, Exception.message(e)}
          end
        end
    end
  end

  # Run custom node validation if the node implements validate/2
  defp run_node_validation(module, inputs, config) do
    if function_exported?(module, :validate, 2) do
      module.validate(inputs, config)
    else
      :ok
    end
  end

  # Handle bypassed node - pass data through from first compatible input to matching outputs
  defp handle_bypassed_node(node, ctx, graph) do
    node_type = node["type"]
    module = Nodes.get_module(node_type)
    {inputs, ctx_after_gather} = gather_inputs(node, ctx, graph)

    Logger.debug("Bypassing node: #{node_type} (#{node["id"]})")

    # Get specs to find type-compatible input→output mappings
    input_spec = if module, do: module.input_spec(), else: []
    output_spec = if module, do: module.output_spec(), else: []

    # Build output map by matching input types to output types
    output =
      Enum.reduce(output_spec, %{}, fn output_def, acc ->
        output_name = output_def[:name] || output_def["name"]
        output_type = output_def[:type] || output_def["type"]

        # Find first input with matching type (or :any type)
        matching_input =
          Enum.find(input_spec, fn input_def ->
            input_type = input_def[:type] || input_def["type"]
            input_type == output_type or input_type == :any or output_type == :any
          end)

        if matching_input do
          input_name = matching_input[:name] || matching_input["name"]
          value = Map.get(inputs, input_name)
          Map.put(acc, output_name, value)
        else
          # No matching input, pass through nil
          Map.put(acc, output_name, nil)
        end
      end)

    {:ok, output, ctx_after_gather}
  end

  # Gather inputs for a node and mark them as consumed for memory GC.
  # Returns {inputs, updated_context} where the context has been updated
  # to decrement consumer counts and potentially free memory.
  defp gather_inputs(node, ctx, graph) do
    edges = graph["edges"] || []

    incoming_edges = Enum.filter(edges, fn e -> e["target"] == node["id"] end)

    # Gather inputs
    inputs =
      Enum.reduce(incoming_edges, %{}, fn edge, acc ->
        source_output = Context.get_output(ctx, edge["source"])
        handle = edge["targetHandle"]
        source_handle = edge["sourceHandle"]

        value =
          if source_output do
            source_output[source_handle]
          else
            Logger.warning("No output found for source node #{edge["source"]}")
            nil
          end

        Map.put(acc, handle, value)
      end)

    # Mark inputs as consumed (for memory GC)
    # This decrements consumer counts and frees outputs when last consumer is done
    updated_ctx =
      Enum.reduce(incoming_edges, ctx, fn edge, acc_ctx ->
        Context.consume_input(acc_ctx, edge["source"])
      end)

    {inputs, updated_ctx}
  end

  defp broadcast(_socket, event, payload) do
    # Use PubSub for broadcasting - works from any process
    Phoenix.PubSub.broadcast(LeaxerCore.PubSub, "runtime:events", {event, payload})
  end

  defp broadcast_progress(state, node_id, node_type, current_index) do
    percentage =
      if state.total_nodes > 0 do
        Float.round((current_index - 1) / state.total_nodes * 100, 1)
      else
        0.0
      end

    broadcast(state.socket, "execution_progress", %{
      job_id: state.job_id,
      graph_progress: %{
        current_index: current_index,
        total_nodes: state.total_nodes,
        percentage: percentage
      },
      node_progress: %{
        node_id: node_id,
        node_type: node_type,
        status: "running",
        current_step: nil,
        total_steps: get_node_total_steps(node_type),
        percentage: 0.0
      }
    })
  end

  defp broadcast_node_complete(state, node_id, index) do
    percentage =
      if state.total_nodes > 0 do
        Float.round(index / state.total_nodes * 100, 1)
      else
        100.0
      end

    broadcast(state.socket, "execution_progress", %{
      job_id: state.job_id,
      graph_progress: %{
        current_index: index,
        total_nodes: state.total_nodes,
        percentage: percentage
      },
      node_progress: %{
        node_id: node_id,
        node_type: nil,
        status: "completed",
        current_step: nil,
        total_steps: nil,
        percentage: 100.0
      }
    })
  end

  # Broadcast node output for real-time preview updates
  defp broadcast_node_output(state, node_id, output) do
    # Only broadcast if there's something useful to show (e.g., preview data)
    serializable_output = sanitize_for_json(output)

    if map_size(serializable_output) > 0 do
      broadcast(state.socket, "node_output", %{
        job_id: state.job_id,
        node_id: node_id,
        output: serializable_output
      })
    end
  end

  # Get total steps for nodes that have step-based progress
  defp get_node_total_steps("GenerateImage") do
    # Get from current model config or default
    case LeaxerCore.Workers.StableDiffusion.current_model() do
      model when is_binary(model) and model != "" ->
        cond do
          String.contains?(model, "sdxl-turbo") -> 4
          String.contains?(model, "turbo") -> 4
          String.contains?(model, "lcm") -> 4
          true -> 20
        end

      _ ->
        20
    end
  rescue
    # UndefinedFunctionError: worker module not available
    UndefinedFunctionError -> 20
  end

  defp get_node_total_steps(_), do: nil

  defp generate_job_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Recursively sanitize data for JSON encoding
  # Removes non-serializable structs (binary data, etc.)
  defp sanitize_for_json(%{__struct__: _} = struct) do
    # Other structs - try to convert to map, or remove if not serializable
    struct |> Map.from_struct() |> sanitize_for_json()
  rescue
    # ArgumentError: struct cannot be converted to map (e.g., binary reference)
    ArgumentError -> :__non_serializable__
  end

  defp sanitize_for_json(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> {k, sanitize_for_json(v)} end)
    |> Enum.reject(fn {_k, v} -> v == :__non_serializable__ end)
    |> Map.new()
  end

  defp sanitize_for_json(data) when is_list(data) do
    data
    |> Enum.map(&sanitize_for_json/1)
    |> Enum.reject(&(&1 == :__non_serializable__))
  end

  defp sanitize_for_json(data), do: data
end
