defmodule LeaxerCore.Nodes.Dataset.RoundRobin do
  @moduledoc """
  Cycle through list items on each execution (0, 1, 2, ..., N, 0, ...).

  Essential for batch generation without manual duplication.
  Uses ETS-backed state to maintain position across executions.

  ## Examples

      iex> RoundRobin.process(%{"items" => ["a", "b", "c"]}, %{"node_id" => "node1"})
      {:ok, %{"current" => "a", "index" => 0}}

      iex> RoundRobin.process(%{"items" => ["a", "b", "c"]}, %{"node_id" => "node1"})
      {:ok, %{"current" => "b", "index" => 1}}

  ## ETS Concurrency Model

  **Table**: `:node_state` (shared with Counter, created in Application.start)

  **Key Format**: `{:round_robin, node_id}`

  ### Access Pattern

  Each round-robin node uses a unique key based on its `node_id`. Multiple
  round-robin nodes in the same workflow use separate keys and do not interfere.

  ### Concurrency Considerations

  - **Sequential execution**: Workflows execute nodes sequentially (topological
    order), so concurrent access to the same round-robin is not expected.
  - **Non-atomic update**: The lookup-calculate-insert sequence is not atomic.
    If parallel execution were enabled, two processes could read the same index
    and both advance to the same next position. This is acceptable under current
    sequential execution but would need `ets:update_counter/3` for parallel support.
  - **Cross-workflow safety**: Different workflows using the same node_id will
    share round-robin state. This is intentional for consistent cycling across
    multiple workflow executions.

  ### Table Ownership

  The `:node_state` table is created at application startup and owned by the
  supervisor, not by individual nodes. Round-robin position survives node restarts.
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "RoundRobin"

  @impl true
  def label, do: "Round Robin"

  @impl true
  def category, do: "Data/List"

  @impl true
  def description, do: "Cycle through list items on each execution"

  @impl true
  def input_spec do
    %{
      items: %{
        type: {:list, :string},
        label: "ITEMS",
        description: "List of items to cycle through"
      },
      reset: %{
        type: :boolean,
        label: "RESET",
        default: false,
        optional: true,
        description: "Reset counter to 0"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      current: %{
        type: :string,
        label: "CURRENT",
        description: "Current item in the cycle"
      },
      index: %{
        type: :integer,
        label: "INDEX",
        description: "Current index (0-based)"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    items = inputs["items"] || config["items"] || []
    reset = inputs["reset"] || config["reset"] || false
    node_id = config["node_id"] || "default"

    if items == [] or not is_list(items) do
      {:error, "Items must be a non-empty list"}
    else
      cycle_items(items, node_id, reset)
    end
  rescue
    e ->
      Logger.error("RoundRobin exception: #{inspect(e)}")
      {:error, "Failed to cycle items: #{Exception.message(e)}"}
  end

  defp cycle_items(items, node_id, reset) do
    key = {:round_robin, node_id}
    item_count = length(items)

    # Reset counter if requested
    if reset do
      :ets.insert(:node_state, {key, 0})
    end

    # Get and increment counter (wraps around at item_count)
    current_index =
      case :ets.lookup(:node_state, key) do
        [{^key, index}] ->
          next_index = rem(index + 1, item_count)
          :ets.insert(:node_state, {key, next_index})
          index

        [] ->
          # First time - initialize to 0, return 0, next will be 1
          :ets.insert(:node_state, {key, 1})
          0
      end

    current_item = Enum.at(items, current_index)

    {:ok,
     %{
       "current" => current_item,
       "index" => current_index
     }}
  end
end
