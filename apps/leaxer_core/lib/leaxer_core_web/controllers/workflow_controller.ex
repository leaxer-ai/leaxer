defmodule LeaxerCoreWeb.WorkflowController do
  @moduledoc """
  REST API controller for workflow operations.

  Provides endpoints for:
  - Workflow file CRUD (list, get, save, delete)
  - Workflow validation
  """
  use LeaxerCoreWeb, :controller

  alias LeaxerCore.Paths

  # ============================================================================
  # Workflow File Operations
  # ============================================================================

  @doc """
  GET /api/workflows

  Lists all workflow files in the workflows directory.

  Response:
  ```json
  {
    "workflows": [
      {"name": "my-workflow", "filename": "my-workflow.lxr", "modified_at": "2024-01-15T10:30:00Z"},
      ...
    ]
  }
  ```
  """
  def index(conn, _params) do
    workflows_dir = Paths.workflows_dir()

    workflows =
      case File.ls(workflows_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".lxr"))
          |> Enum.map(fn filename ->
            path = Path.join(workflows_dir, filename)
            stat = File.stat!(path)

            %{
              name: String.replace_suffix(filename, ".lxr", ""),
              filename: filename,
              modified_at: stat.mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_iso8601()
            }
          end)
          |> Enum.sort_by(& &1.modified_at, :desc)

        {:error, _} ->
          []
      end

    json(conn, %{workflows: workflows})
  end

  @doc """
  GET /api/workflows/:name

  Gets a specific workflow file by name.

  Response: The workflow JSON content
  """
  def show(conn, %{"name" => name}) do
    filename = ensure_extension(name, ".lxr")
    path = Path.join(Paths.workflows_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, workflow} ->
            # Sanitize on load to clean up existing workflows with embedded image data
            sanitized = sanitize_workflow(workflow)
            json(conn, sanitized)

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Invalid workflow JSON"})
        end

      {:error, :enoent} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to read workflow: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/workflows

  Creates a new workflow file or updates an existing one.

  Request body:
  ```json
  {
    "name": "my-workflow",
    "workflow": { ... workflow content ... }
  }
  ```

  Response:
  ```json
  {
    "success": true,
    "name": "my-workflow",
    "filename": "my-workflow.lxr",
    "path": "/path/to/workflows/my-workflow.lxr"
  }
  ```
  """
  def create(conn, %{"name" => name, "workflow" => workflow}) do
    filename = ensure_extension(name, ".lxr")
    path = Path.join(Paths.workflows_dir(), filename)

    # Ensure workflows directory exists
    File.mkdir_p!(Paths.workflows_dir())

    # Sanitize workflow to remove execution results (base64 images, preview URLs, etc.)
    sanitized_workflow = sanitize_workflow(workflow)

    case Jason.encode(sanitized_workflow, pretty: true) do
      {:ok, content} ->
        case File.write(path, content) do
          :ok ->
            json(conn, %{
              success: true,
              name: String.replace_suffix(filename, ".lxr", ""),
              filename: filename,
              path: path
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to save workflow: #{inspect(reason)}"})
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid workflow data: #{inspect(reason)}"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: name, workflow"})
  end

  @doc """
  DELETE /api/workflows/:name

  Deletes a workflow file.

  Response:
  ```json
  {"success": true}
  ```
  """
  def delete(conn, %{"name" => name}) do
    filename = ensure_extension(name, ".lxr")
    path = Path.join(Paths.workflows_dir(), filename)

    case File.rm(path) do
      :ok ->
        json(conn, %{success: true})

      {:error, :enoent} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete workflow: #{inspect(reason)}"})
    end
  end

  # Helper to ensure filename has correct extension
  defp ensure_extension(name, ext) do
    if String.ends_with?(name, ext), do: name, else: name <> ext
  end

  # Sanitize workflow to remove execution results (transient data that shouldn't be saved)
  # This keeps workflows small and stateless - only configuration is saved, not results
  defp sanitize_workflow(workflow) when is_map(workflow) do
    workflow
    |> update_in_if_exists(["nodes"], fn nodes ->
      Enum.map(nodes, &sanitize_node/1)
    end)
  end

  defp sanitize_workflow(workflow), do: workflow

  defp sanitize_node(node) when is_map(node) do
    node
    |> update_in_if_exists(["data"], &sanitize_node_data/1)
  end

  defp sanitize_node(node), do: node

  # Remove transient execution data from node data
  defp sanitize_node_data(data) when is_map(data) do
    # Keys that contain execution results (not configuration)
    transient_keys = [
      # Image preview/comparison URLs (generated during execution)
      "before_url",
      "after_url",
      "preview_url",
      "image_url",
      # Execution output data
      "output",
      "outputs",
      "result",
      "results",
      # Base64 image data embedded in results
      "preview",
      "previews"
    ]

    data
    |> Map.drop(transient_keys)
    |> Enum.map(fn {key, value} ->
      # Also strip base64 data from any nested image objects
      {key, sanitize_value(value)}
    end)
    |> Map.new()
  end

  defp sanitize_node_data(data), do: data

  # Recursively sanitize values, removing base64 image data
  defp sanitize_value(%{"data" => data, "mime_type" => _}) when is_binary(data) do
    # This is a base64 image object - remove the data, keep structure marker
    # Return nil to indicate "no saved value" rather than a huge base64 string
    nil
  end

  defp sanitize_value(%{data: data, mime_type: _}) when is_binary(data) do
    nil
  end

  # Handle data URLs (data:image/png;base64,...)
  defp sanitize_value(value) when is_binary(value) do
    if String.starts_with?(value, "data:image/") do
      nil
    else
      value
    end
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp sanitize_value(value) when is_map(value) do
    # Check if this looks like an image object with base64 data
    cond do
      Map.has_key?(value, "data") and Map.has_key?(value, "mime_type") ->
        nil

      Map.has_key?(value, :data) and Map.has_key?(value, :mime_type) ->
        nil

      true ->
        value
        |> Enum.map(fn {k, v} -> {k, sanitize_value(v)} end)
        |> Enum.filter(fn {_k, v} -> v != nil end)
        |> Map.new()
    end
  end

  defp sanitize_value(value), do: value

  defp update_in_if_exists(map, keys, fun) when is_map(map) do
    case get_in(map, keys) do
      nil -> map
      value -> put_in(map, keys, fun.(value))
    end
  end

  defp update_in_if_exists(map, _keys, _fun), do: map

  # ============================================================================
  # Workflow Validation
  # ============================================================================

  @doc """
  POST /api/workflow/validate

  Validates a workflow against the current system state.
  Checks for:
  - Missing node types
  - Missing models
  - Version compatibility

  Request body:
  ```json
  {
    "workflow": {
      "format_version": "0.1.0",
      "requirements": {
        "node_types": ["KSampler", "CLIPTextEncode"],
        "models": ["sd_xl_base_1.0.safetensors"]
      }
    }
  }
  ```

  Response:
  ```json
  {
    "valid": true|false,
    "errors": [
      {"type": "missing_node", "node_type": "...", "message": "..."},
      {"type": "missing_model", "model_name": "...", "message": "..."}
    ]
  }
  ```
  """
  def validate(conn, %{"workflow" => workflow_params}) do
    errors = validate_workflow(workflow_params)

    conn
    |> put_status(:ok)
    |> json(%{
      valid: Enum.empty?(errors),
      errors: errors
    })
  end

  def validate(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      valid: false,
      errors: [%{type: "invalid_format", message: "Missing workflow parameter"}]
    })
  end

  # Validate the workflow and return a list of errors
  defp validate_workflow(workflow_params) do
    errors = []

    # Validate node types
    errors =
      case Map.get(workflow_params, "requirements") do
        %{"node_types" => node_types} when is_list(node_types) ->
          errors ++ validate_node_types(node_types)

        _ ->
          errors
      end

    # Validate models (optional)
    errors =
      case Map.get(workflow_params, "requirements") do
        %{"models" => models} when is_list(models) ->
          errors ++ validate_models(models)

        _ ->
          errors
      end

    errors
  end

  defp validate_node_types(node_types) do
    available_nodes = LeaxerCore.Nodes.list_types()

    node_types
    |> Enum.filter(fn type ->
      not Enum.member?(available_nodes, type)
    end)
    |> Enum.map(fn missing_type ->
      %{
        type: "missing_node",
        node_type: missing_type,
        message:
          "Node type '#{missing_type}' is not available. Install the required custom node or check spelling."
      }
    end)
  end

  defp validate_models(models) do
    # Get available models from the Models module if it exists
    # Use apply/3 to avoid compile-time warning about undefined module
    available_models =
      if Code.ensure_loaded?(LeaxerCore.Models) and
           function_exported?(LeaxerCore.Models, :list_all, 0) do
        apply(LeaxerCore.Models, :list_all, [])
        |> Enum.map(& &1.name)
      else
        # If Models module doesn't exist, skip model validation
        []
      end

    # If we have no available models info, skip validation
    if Enum.empty?(available_models) do
      []
    else
      models
      |> Enum.filter(fn model ->
        not Enum.member?(available_models, model)
      end)
      |> Enum.map(fn missing_model ->
        %{
          type: "missing_model",
          model_name: missing_model,
          message:
            "Model '#{missing_model}' is not available. Download the model or check the path."
        }
      end)
    end
  end
end
