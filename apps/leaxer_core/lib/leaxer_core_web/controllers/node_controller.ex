defmodule LeaxerCoreWeb.NodeController do
  @moduledoc """
  REST API controller for node metadata.

  Provides endpoints for the frontend to discover available nodes
  and their specifications.
  """
  use LeaxerCoreWeb, :controller

  @doc """
  GET /api/nodes

  Returns all registered nodes with their metadata.
  """
  def index(conn, _params) do
    nodes = LeaxerCore.Nodes.list_all_with_metadata()

    conn
    |> put_status(:ok)
    |> json(%{
      nodes: Enum.map(nodes, &serialize_node/1),
      stats: LeaxerCore.Nodes.stats()
    })
  end

  @doc """
  GET /api/nodes/:type

  Returns metadata for a specific node type.
  """
  def show(conn, %{"type" => type}) do
    case LeaxerCore.Nodes.get_metadata(type) do
      {:ok, metadata} ->
        conn
        |> put_status(:ok)
        |> json(%{node: serialize_node(metadata)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Node type '#{type}' not found"})
    end
  end

  @doc """
  POST /api/nodes/reload

  Reloads custom nodes from the custom_nodes directory.
  """
  def reload(conn, _params) do
    case LeaxerCore.Nodes.reload_custom_nodes() do
      {:ok, count} ->
        conn
        |> put_status(:ok)
        |> json(%{
          message: "Reloaded custom nodes",
          count: count,
          stats: LeaxerCore.Nodes.stats()
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to reload: #{inspect(reason)}"})
    end
  end

  # Serialize node metadata to JSON-friendly format
  defp serialize_node(node) do
    %{
      type: node.type,
      label: node.label,
      category: node.category,
      category_path: node.category_path,
      description: node.description,
      input_spec: serialize_spec(node.input_spec),
      output_spec: serialize_spec(node.output_spec),
      config_spec: serialize_spec(node.config_spec),
      default_config: node.default_config,
      ui_component: serialize_ui_component(node.ui_component),
      source: to_string(node.source)
    }
  end

  # Convert atom keys to strings and handle nested structures
  defp serialize_spec(spec) when is_map(spec) do
    Enum.into(spec, %{}, fn {key, value} ->
      {to_string(key), serialize_field_spec(value)}
    end)
  end

  defp serialize_field_spec(field) when is_map(field) do
    Enum.into(field, %{}, fn {key, value} ->
      serialized_value =
        case {key, value} do
          # Simple atom type: :image -> "image"
          {:type, type} when is_atom(type) ->
            to_string(type)

          # Tuple type: {:list, :image} -> "list:image"
          {:type, {container, inner}} when is_atom(container) and is_atom(inner) ->
            "#{container}:#{inner}"

          {:options, options} when is_list(options) ->
            Enum.map(options, &serialize_option/1)

          {_, v} when is_atom(v) ->
            to_string(v)

          {_, v} when is_tuple(v) ->
            inspect(v)

          {_, v} ->
            v
        end

      {to_string(key), serialized_value}
    end)
  end

  defp serialize_field_spec(value), do: value

  defp serialize_option(option) when is_map(option) do
    Enum.into(option, %{}, fn {k, v} ->
      {to_string(k), v}
    end)
  end

  defp serialize_option(value), do: value

  defp serialize_ui_component(:auto), do: "auto"
  defp serialize_ui_component({:custom, name}), do: %{"custom" => name}
  defp serialize_ui_component(other), do: inspect(other)
end
