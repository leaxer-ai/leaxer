defmodule LeaxerCore.ExecutionState do
  @moduledoc """
  Stores the current execution state for progress persistence across browser refresh.
  Uses ETS for fast reads and a GenServer for state management.

  ## Supervision

  - **Restart**: Permanent (always restarted)
  - **Strategy**: Part of main supervision tree with `:one_for_one`
  - **ETS Table**: `:leaxer_execution_state` with `read_concurrency: true`

  ## Failure Modes

  - **GenServer crash**: ETS table is lost (not named_table owned by supervisor).
    `available?/0` returns false until restart completes.
  - **Runtime queries before init**: All public functions check `available?/0`
    and gracefully return nil or `:ok` instead of crashing.

  ## State Recovery

  On restart, the ETS table is recreated empty. Any in-progress execution will
  appear as "not running" to refreshed browser clients. The Runtime process
  will re-populate state when it next updates progress.

  ## Design Note

  This module exists specifically to allow browser refreshes during long-running
  executions. The ETS table provides fast concurrent reads for the WebSocket
  channel without blocking the Runtime or Queue processes.

  ## ETS Concurrency Model

  **Table**: `:leaxer_execution_state`

  **Configuration**: `:set`, `:public`, `:named_table`, `read_concurrency: true`

  ### Access Pattern

  - **Readers**: WebSocket channels polling `get_state/0` (high frequency, concurrent)
  - **Writers**: Runtime process via GenServer casts (low frequency, serialized)

  ### Concurrency Guarantees

  - **Read safety**: Multiple processes can read simultaneously without blocking.
    The `read_concurrency: true` flag optimizes the internal lock structure for
    concurrent readers.
  - **Write safety**: All writes go through GenServer callbacks (`handle_call`,
    `handle_cast`), ensuring serial access. Only one write operation executes
    at a time.
  - **Read-write isolation**: Readers see a consistent snapshot. An in-progress
    write does not affect concurrent reads until the write completes.

  ### Operations

  | Operation | Access | Frequency | Notes |
  |-----------|--------|-----------|-------|
  | `get_state/0` | Read | High | Direct ETS lookup, bypasses GenServer |
  | `start_execution/1` | Write | Low | GenServer call, inserts initial state |
  | `set_current_node/3` | Write | Low | GenServer cast, updates current node |
  | `set_step_progress/4` | Write | Low | GenServer cast, updates step progress |
  | `complete_execution/0` | Write | Low | GenServer cast, deletes state |

  ### Single-Key Design

  All state is stored under a single key (`:state`), making each operation atomic.
  There are no multi-key transactions or race conditions between keys.
  """

  use GenServer
  require Logger

  @table_name :leaxer_execution_state

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if the ExecutionState GenServer is available.
  Returns true if the ETS table has been created, false otherwise.
  """
  def available? do
    :ets.whereis(@table_name) != :undefined
  end

  @doc """
  Sets the execution as started with the given node IDs.
  Returns :ok on success, {:error, :not_available} if GenServer not started.
  """
  def start_execution(node_ids) when is_list(node_ids) do
    if available?() do
      GenServer.call(__MODULE__, {:start_execution, node_ids})
    else
      {:error, :not_available}
    end
  end

  @doc """
  Updates the current node being executed.
  Silently ignores if GenServer not started.
  """
  def set_current_node(node_id, index, total) do
    if available?() do
      GenServer.cast(__MODULE__, {:set_current_node, node_id, index, total})
    end

    :ok
  end

  @doc """
  Updates the step progress for a node.
  Silently ignores if GenServer not started.
  """
  def set_step_progress(node_id, current_step, total_steps, percentage) do
    if available?() do
      GenServer.cast(
        __MODULE__,
        {:set_step_progress, node_id, current_step, total_steps, percentage}
      )
    end

    :ok
  end

  @doc """
  Marks execution as complete.
  Silently ignores if GenServer not started.
  """
  def complete_execution do
    if available?() do
      GenServer.cast(__MODULE__, :complete_execution)
    end

    :ok
  end

  @doc """
  Gets the current execution state.
  Returns nil if no execution is in progress or if the ETS table hasn't been created yet.
  """
  def get_state do
    case :ets.whereis(@table_name) do
      :undefined ->
        # ETS table not yet created (GenServer not started)
        nil

      _tid ->
        case :ets.lookup(@table_name, :state) do
          [{:state, state}] -> state
          [] -> nil
        end
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast concurrent reads
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true
    ])

    {:ok, %{}}
  end

  @impl true
  def handle_call({:start_execution, node_ids}, _from, state) do
    execution_state = %{
      is_executing: true,
      node_ids: node_ids,
      current_node: nil,
      current_index: 0,
      total_nodes: length(node_ids),
      step_progress: nil,
      started_at: System.monotonic_time(:millisecond)
    }

    :ets.insert(@table_name, {:state, execution_state})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:set_current_node, node_id, index, total}, state) do
    case :ets.lookup(@table_name, :state) do
      [{:state, execution_state}] ->
        updated = %{
          execution_state
          | current_node: node_id,
            current_index: index,
            total_nodes: total,
            step_progress: nil
        }

        :ets.insert(@table_name, {:state, updated})

      [] ->
        # No execution in progress, ignore
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:set_step_progress, node_id, current_step, total_steps, percentage}, state) do
    case :ets.lookup(@table_name, :state) do
      [{:state, execution_state}] ->
        updated = %{
          execution_state
          | current_node: node_id,
            step_progress: %{
              current_step: current_step,
              total_steps: total_steps,
              percentage: percentage
            }
        }

        :ets.insert(@table_name, {:state, updated})

      [] ->
        # No execution in progress, ignore
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:complete_execution, state) do
    :ets.delete(@table_name, :state)
    {:noreply, state}
  end
end
