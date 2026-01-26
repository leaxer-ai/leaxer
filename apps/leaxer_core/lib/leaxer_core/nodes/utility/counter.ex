defmodule LeaxerCore.Nodes.Utility.Counter do
  @moduledoc """
  Auto-increment integer for batch numbering.

  Essential for unique filenames in batch saves.
  Uses ETS-backed state to maintain counter across executions.

  ## Examples

      iex> Counter.process(%{}, %{"node_id" => "node1", "start" => 1})
      {:ok, %{"value" => 1}}

      iex> Counter.process(%{}, %{"node_id" => "node1", "start" => 1})
      {:ok, %{"value" => 2}}

  ## ETS Concurrency Model

  **Table**: `:node_state` (shared with RoundRobin, created in Application.start)

  **Key Format**: `{:counter, node_id}`

  ### Access Pattern

  Each counter node uses a unique key based on its `node_id`. Multiple counter
  nodes in the same workflow use separate keys and do not interfere.

  ### Concurrency Considerations

  - **Sequential execution**: Workflows execute nodes sequentially (topological
    order), so concurrent access to the same counter is not expected.
  - **Non-atomic increment**: The lookup-increment-insert sequence is not atomic.
    If parallel execution were enabled, two processes could read the same value
    and both increment to the same next value. This is acceptable under current
    sequential execution but would need `ets:update_counter/3` for parallel support.
  - **Cross-workflow safety**: Different workflows using the same node_id will
    share counter state. This is intentional for batch numbering continuity.

  ### Table Ownership

  The `:node_state` table is created at application startup and owned by the
  supervisor, not by individual nodes. Counter state survives node restarts.
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "Counter"

  @impl true
  def label, do: "Counter"

  @impl true
  def category, do: "Utility/Random"

  @impl true
  def description, do: "Auto-increment integer for batch numbering"

  @impl true
  def input_spec do
    %{
      start: %{
        type: :integer,
        label: "START",
        default: 1,
        optional: true,
        description: "Starting counter value"
      },
      reset: %{
        type: :boolean,
        label: "RESET",
        default: false,
        optional: true,
        description: "Reset counter to start value"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      value: %{
        type: :integer,
        label: "VALUE",
        description: "Current counter value"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    start = inputs["start"] || config["start"] || 1
    reset = inputs["reset"] || config["reset"] || false
    node_id = config["node_id"] || "default"

    increment_counter(node_id, start, reset)
  rescue
    e ->
      Logger.error("Counter exception: #{inspect(e)}")
      {:error, "Failed to increment counter: #{Exception.message(e)}"}
  end

  defp increment_counter(node_id, start, reset) do
    key = {:counter, node_id}

    # Reset counter if requested
    if reset do
      :ets.insert(:node_state, {key, start})
    end

    # Get current value and increment
    current =
      case :ets.lookup(:node_state, key) do
        [{^key, value}] ->
          :ets.insert(:node_state, {key, value + 1})
          value

        [] ->
          # First time - initialize to start, return start, next will be start + 1
          :ets.insert(:node_state, {key, start + 1})
          start
      end

    {:ok, %{"value" => current}}
  end
end
