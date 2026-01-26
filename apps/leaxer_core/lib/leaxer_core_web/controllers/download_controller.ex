defmodule LeaxerCoreWeb.DownloadController do
  @moduledoc """
  REST API controller for model download management.

  Provides endpoints for starting, monitoring, and managing model downloads
  from remote registries to local storage directories.
  """
  use LeaxerCoreWeb, :controller

  alias LeaxerCore.Models.{DownloadManager, Registry}

  @doc """
  POST /api/downloads/start

  Start downloading a model by ID from the registry.

  Request body:
  - model_id: Model ID from registry (required)
  - target_dir: Optional override for target directory

  Returns:
  - download_id: Unique identifier for tracking download progress
  - message: Success message
  """
  def start(conn, %{"model_id" => model_id} = params) do
    target_dir = Map.get(params, "target_dir")

    case DownloadManager.start_download(model_id, target_dir) do
      {:ok, download_id} ->
        conn
        |> put_status(:ok)
        |> json(%{
          download_id: download_id,
          model_id: model_id,
          message: "Download started successfully"
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to start download", reason: reason})
    end
  end

  @doc """
  DELETE /api/downloads/:id

  Cancel an active download.

  Returns:
  - message: Success/error message
  """
  def cancel(conn, %{"id" => download_id}) do
    case DownloadManager.cancel_download(download_id) do
      :ok ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Download cancelled successfully"})

      {:error, reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Failed to cancel download", reason: reason})
    end
  end

  @doc """
  GET /api/downloads/:id

  Get progress information for a specific download.

  Returns:
  - progress: Complete download progress information including status, bytes, speed
  """
  def show(conn, %{"id" => download_id}) do
    case DownloadManager.get_progress(download_id) do
      {:ok, progress} ->
        conn
        |> put_status(:ok)
        |> json(%{progress: progress})

      {:error, reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Download not found", reason: reason})
    end
  end

  @doc """
  GET /api/downloads

  List all downloads with optional status filtering.

  Query params:
  - active_only: true/false - only return active downloads (default: false)

  Returns:
  - downloads: List of download progress information
  - count: Total number of downloads
  """
  def index(conn, params) do
    active_only = Map.get(params, "active_only", "false") == "true"

    result =
      if active_only do
        DownloadManager.list_active()
      else
        DownloadManager.list_all()
      end

    case result do
      {:ok, downloads} ->
        conn
        |> put_status(:ok)
        |> json(%{
          downloads: downloads,
          count: length(downloads),
          active_only: active_only
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to list downloads", reason: reason})
    end
  end

  @doc """
  GET /api/registry/models

  Get models from the registry with optional category filtering.

  Query params:
  - category: Filter by category (checkpoints/loras/vaes/controlnets/llms/etc)

  Returns:
  - registry: Registry data (all categories or specific category)
  - category: Category filter applied (if any)
  """
  def registry(conn, params) do
    category = Map.get(params, "category")

    result =
      if category do
        Registry.get_by_category(category)
      else
        Registry.get_all()
      end

    case result do
      {:ok, data} ->
        conn
        |> put_status(:ok)
        |> json(%{
          registry: data,
          category: category,
          generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to fetch registry", reason: reason})
    end
  end
end
