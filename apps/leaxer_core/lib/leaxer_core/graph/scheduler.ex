defmodule LeaxerCore.Graph.Scheduler do
  @moduledoc """
  Schedules nodes using depth-aware Kahn's algorithm.

  Prioritizes shallower nodes (closer to outputs) to ensure preview/output
  nodes execute as soon as their inputs are ready, rather than waiting for
  deeper branches to complete first.

  Depth is calculated as distance from output nodes (outputs = depth 1).

  ## Execution Layers

  The scheduler returns nodes grouped into layers. Nodes within the same layer
  have no dependencies on each other and can be executed in parallel.

  ## Node Ordering

  For tie-breaking between nodes at the same depth, the scheduler uses timestamps
  to ensure deterministic ordering. Timestamps are extracted from node data:

  1. **Primary**: `data.created_at` field (explicit timestamp in milliseconds)
  2. **Fallback**: Parse timestamp from node ID (legacy `node_<timestamp>_<random>` format)

  Newer nodes (higher timestamps) are prioritized for execution, ensuring that
  the most recently added nodes in a parallel branch execute first.
  """

  @doc """
  Schedule nodes for execution, returning layers for parallel execution.

  Returns `{:ok, [[node_id, ...], ...]}` where each inner list is a layer
  of nodes that can be executed in parallel.
  """
  @spec schedule(map(), list()) :: {:ok, [[String.t()]]} | {:error, :cycle_detected, map()}
  def schedule(nodes, edges) do
    node_ids = Map.keys(nodes)
    {adjacency, in_degree} = build_graph(node_ids, edges)

    # Calculate depths (distance from output nodes, where outputs = depth 1)
    depths = calculate_depths(node_ids, edges)

    # Sort initial ready nodes by depth ASCENDING, timestamp desc as tiebreaker
    ready_queue =
      node_ids
      |> Enum.filter(fn id -> Map.get(in_degree, id, 0) == 0 end)
      |> Enum.sort_by(fn id ->
        {Map.get(depths, id, 0), -get_node_timestamp(nodes, id)}
      end)

    kahn_sort_layers(ready_queue, adjacency, in_degree, depths, nodes, [], length(node_ids))
  end

  @doc """
  Schedule nodes for execution, returning a flat list (legacy API).

  This is the original API that returns a flat list of node IDs.
  Use `schedule/2` for the new layer-based API.
  """
  @spec schedule_flat(map(), list()) :: {:ok, [String.t()]} | {:error, :cycle_detected, map()}
  def schedule_flat(nodes, edges) do
    case schedule(nodes, edges) do
      {:ok, layers} -> {:ok, List.flatten(layers)}
      error -> error
    end
  end

  @spec calculate_depths(list(), list()) :: %{String.t() => non_neg_integer()}
  defp calculate_depths(node_ids, edges) do
    # Build forward adjacency to find output nodes (out_degree == 0)
    forward_adj =
      Enum.reduce(edges, %{}, fn edge, acc ->
        Map.update(acc, edge["source"], [edge["target"]], &[edge["target"] | &1])
      end)

    # Output nodes have no outgoing edges
    output_nodes =
      Enum.filter(node_ids, fn id ->
        Map.get(forward_adj, id, []) == []
      end)

    # Build reverse adjacency (target -> sources)
    reverse_adj =
      Enum.reduce(edges, %{}, fn edge, acc ->
        Map.update(acc, edge["target"], [edge["source"]], &[edge["source"] | &1])
      end)

    # BFS from outputs, calculating depths
    initial_depths = Map.new(output_nodes, fn id -> {id, 1} end)
    bfs_depths(output_nodes, reverse_adj, initial_depths)
  end

  defp bfs_depths([], _reverse_adj, depths), do: depths

  defp bfs_depths([current | rest], reverse_adj, depths) do
    current_depth = Map.get(depths, current, 1)
    predecessors = Map.get(reverse_adj, current, [])

    {new_depths, new_queue} =
      Enum.reduce(predecessors, {depths, rest}, fn pred, {d, q} ->
        new_depth = current_depth + 1

        if new_depth > Map.get(d, pred, 0) do
          {Map.put(d, pred, new_depth), q ++ [pred]}
        else
          {d, q}
        end
      end)

    bfs_depths(new_queue, reverse_adj, new_depths)
  end

  defp build_graph(node_ids, edges) do
    in_degree = Map.new(node_ids, fn id -> {id, 0} end)

    Enum.reduce(edges, {%{}, in_degree}, fn edge, {adj, deg} ->
      source = edge["source"]
      target = edge["target"]
      adj = Map.update(adj, source, [target], &[target | &1])
      deg = Map.update(deg, target, 1, &(&1 + 1))
      {adj, deg}
    end)
  end

  # Layer-based Kahn's sort - groups nodes into execution layers
  # Nodes in the same layer have no dependencies on each other and can run in parallel
  defp kahn_sort_layers(ready_queue, adjacency, in_degree, depths, nodes, layers, expected) do
    kahn_sort_layers_impl(ready_queue, adjacency, in_degree, depths, nodes, layers, 0, expected)
  end

  defp kahn_sort_layers_impl([], _adj, _deg, _depths, _nodes, layers, processed, expected) do
    if processed == expected,
      do: {:ok, Enum.reverse(layers)},
      else: {:error, :cycle_detected, %{}}
  end

  defp kahn_sort_layers_impl(
         ready_queue,
         adjacency,
         in_degree,
         depths,
         nodes,
         layers,
         processed,
         expected
       ) do
    # Sort ready nodes by depth ASC, timestamp DESC as tiebreaker
    sorted_layer =
      Enum.sort_by(ready_queue, fn id ->
        {Map.get(depths, id, 0), -get_node_timestamp(nodes, id)}
      end)

    # Process all nodes in this layer to find the next layer
    {updated_in_degree, next_ready} =
      Enum.reduce(sorted_layer, {in_degree, []}, fn node_id, {deg_acc, ready_acc} ->
        neighbors = Map.get(adjacency, node_id, [])

        Enum.reduce(neighbors, {deg_acc, ready_acc}, fn neighbor, {deg, ready} ->
          new_deg = Map.get(deg, neighbor, 0) - 1
          deg = Map.put(deg, neighbor, new_deg)
          if new_deg == 0, do: {deg, [neighbor | ready]}, else: {deg, ready}
        end)
      end)

    # Continue with the next layer
    kahn_sort_layers_impl(
      next_ready,
      adjacency,
      updated_in_degree,
      depths,
      nodes,
      [sorted_layer | layers],
      processed + length(sorted_layer),
      expected
    )
  end

  # Get timestamp for a node, preferring explicit created_at field over ID parsing.
  # This decouples scheduling from ID format conventions.
  @spec get_node_timestamp(map(), String.t()) :: non_neg_integer()
  defp get_node_timestamp(nodes, node_id) do
    node_data = Map.get(nodes, node_id, %{})

    # Try to get created_at from node data (may be in "data" submap or at top level)
    cond do
      # Check data.created_at (primary location from frontend)
      is_map(node_data["data"]) and is_integer(node_data["data"]["created_at"]) ->
        node_data["data"]["created_at"]

      # Check top-level created_at (alternative location)
      is_integer(node_data["created_at"]) ->
        node_data["created_at"]

      # Fallback: parse timestamp from legacy node ID format (node_<timestamp>_<random>)
      true ->
        extract_timestamp_from_id(node_id)
    end
  end

  # Legacy ID parsing for backward compatibility with nodes created before
  # the explicit created_at field was added.
  defp extract_timestamp_from_id(node_id) do
    case String.split(node_id, "_") do
      ["node", timestamp | _] ->
        case Integer.parse(timestamp) do
          {ts, _} -> ts
          :error -> 0
        end

      _ ->
        0
    end
  end
end
