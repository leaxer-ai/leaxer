defmodule LeaxerCore.Graph.Execution do
  @moduledoc """
  Parses JSON graph and performs topological sort for execution scheduling.
  """

  alias LeaxerCore.Nodes.Registry

  @type graph_json :: map()
  @type sorted_layers :: [[String.t()]]

  @doc """
  Sort and validate a graph, returning execution layers.

  Returns `{:ok, layers}` where each layer is a list of node IDs that can
  be executed in parallel.
  """
  @spec sort_and_validate(graph_json()) :: {:ok, sorted_layers()} | {:error, atom(), map()}
  def sort_and_validate(graph_json) do
    with {:ok, nodes, edges} <- parse_json(graph_json),
         :ok <- validate_connections(nodes, edges),
         {:ok, layers} <- topological_sort(nodes, edges) do
      {:ok, layers}
    end
  end

  defp parse_json(%{"nodes" => nodes, "edges" => edges}) do
    {:ok, nodes, edges}
  end

  defp parse_json(_), do: {:error, :invalid_graph_format, %{}}

  defp topological_sort(nodes, edges) do
    LeaxerCore.Graph.Scheduler.schedule(nodes, edges)
  end

  # Validates graph connections:
  # 1. All edges reference existing nodes
  # 2. Source handles are outputs, target handles are inputs
  # 3. Each input has at most one connection
  # 4. Connected types must match
  defp validate_connections(nodes, edges) do
    node_ids = Map.keys(nodes)

    with :ok <- validate_edges_reference_nodes(edges, node_ids),
         :ok <- validate_handle_directions(nodes, edges),
         :ok <- validate_single_input_connections(edges),
         :ok <- validate_type_matching(nodes, edges) do
      :ok
    end
  end

  # Validate all edges reference existing nodes
  defp validate_edges_reference_nodes(edges, node_ids) do
    node_set = MapSet.new(node_ids)

    invalid_edge =
      Enum.find(edges, fn edge ->
        source = edge["source"]
        target = edge["target"]
        not MapSet.member?(node_set, source) or not MapSet.member?(node_set, target)
      end)

    case invalid_edge do
      nil ->
        :ok

      edge ->
        {:error, :invalid_edge_reference,
         %{
           message: "Edge references non-existent node",
           source: edge["source"],
           target: edge["target"]
         }}
    end
  end

  # Validate source handles are outputs and target handles are inputs
  defp validate_handle_directions(nodes, edges) do
    invalid_edge =
      Enum.find(edges, fn edge ->
        source_node = nodes[edge["source"]]
        target_node = nodes[edge["target"]]
        source_handle = edge["sourceHandle"]
        target_handle = edge["targetHandle"]

        source_type = source_node["type"]
        target_type = target_node["type"]

        source_spec = Registry.get_spec(source_type)
        target_spec = Registry.get_spec(target_type)

        # Source handle must be an output (use safe_handle_to_atom to prevent atom exhaustion)
        source_handle_atom = safe_handle_to_atom(source_handle)

        source_is_output =
          source_spec && source_handle_atom &&
            Map.has_key?(source_spec.output_spec, source_handle_atom)

        # Target handle must be an input
        target_handle_atom = safe_handle_to_atom(target_handle)

        target_is_input =
          target_spec && target_handle_atom &&
            Map.has_key?(target_spec.input_spec, target_handle_atom)

        not source_is_output or not target_is_input
      end)

    case invalid_edge do
      nil ->
        :ok

      edge ->
        {:error, :invalid_handle_direction,
         %{
           message: "Connection must go from output to input",
           source: edge["source"],
           source_handle: edge["sourceHandle"],
           target: edge["target"],
           target_handle: edge["targetHandle"]
         }}
    end
  end

  # Validate each input handle has at most one connection
  defp validate_single_input_connections(edges) do
    # Group edges by target + targetHandle
    input_connections =
      Enum.group_by(edges, fn edge ->
        {edge["target"], edge["targetHandle"]}
      end)

    # Find any input with multiple connections
    multi_connected =
      Enum.find(input_connections, fn {_key, conns} ->
        length(conns) > 1
      end)

    case multi_connected do
      nil ->
        :ok

      {{target, handle}, _conns} ->
        {:error, :multiple_input_connections,
         %{
           message: "Input can only have one connection",
           target: target,
           target_handle: handle
         }}
    end
  end

  # Validate connected types match
  defp validate_type_matching(nodes, edges) do
    invalid_edge =
      Enum.find(edges, fn edge ->
        source_node = nodes[edge["source"]]
        target_node = nodes[edge["target"]]
        source_handle = edge["sourceHandle"]
        target_handle = edge["targetHandle"]

        source_type = source_node["type"]
        target_type = target_node["type"]

        source_spec = Registry.get_spec(source_type)
        target_spec = Registry.get_spec(target_type)

        source_data_type = get_output_type(source_spec, source_handle)
        target_data_type = get_input_type(target_spec, target_handle)

        # Types must match (or one is :any)
        source_data_type != target_data_type and
          source_data_type != :any and
          target_data_type != :any
      end)

    case invalid_edge do
      nil ->
        :ok

      edge ->
        source_node = nodes[edge["source"]]
        target_node = nodes[edge["target"]]
        source_spec = Registry.get_spec(source_node["type"])
        target_spec = Registry.get_spec(target_node["type"])

        {:error, :type_mismatch,
         %{
           message: "Connected handles have incompatible types",
           source: edge["source"],
           source_handle: edge["sourceHandle"],
           source_type: get_output_type(source_spec, edge["sourceHandle"]),
           target: edge["target"],
           target_handle: edge["targetHandle"],
           target_type: get_input_type(target_spec, edge["targetHandle"])
         }}
    end
  end

  defp get_output_type(nil, _handle), do: nil

  defp get_output_type(spec, handle) do
    # Use safe_handle_to_atom to prevent atom table exhaustion from malicious handles
    case safe_handle_to_atom(handle) do
      nil ->
        nil

      handle_atom ->
        case Map.get(spec.output_spec, handle_atom) do
          nil -> nil
          field -> normalize_type(field.type)
        end
    end
  end

  defp get_input_type(nil, _handle), do: nil

  defp get_input_type(spec, handle) do
    # Use safe_handle_to_atom to prevent atom table exhaustion from malicious handles
    case safe_handle_to_atom(handle) do
      nil ->
        nil

      handle_atom ->
        case Map.get(spec.input_spec, handle_atom) do
          nil -> nil
          field -> normalize_type(field.type)
        end
    end
  end

  # Normalize type for comparison (handles tuples like {:list, :string})
  defp normalize_type({:list, inner_type}), do: {:list, inner_type}
  defp normalize_type(type) when is_atom(type), do: type
  defp normalize_type(_), do: :any

  # Convert handle string to existing atom to prevent atom table exhaustion.
  # Returns nil if the atom doesn't exist, indicating an invalid handle name.
  @spec safe_handle_to_atom(String.t()) :: atom() | nil
  defp safe_handle_to_atom(handle) when is_binary(handle) do
    String.to_existing_atom(handle)
  rescue
    ArgumentError -> nil
  end
end
