defmodule LeaxerCoreWeb.DownloadChannel do
  @moduledoc """
  WebSocket channel for model download management and progress tracking.

  Provides real-time communication for model downloads between the frontend
  and the DownloadManager GenServer, with progress updates and registry access.

  ## Supported Events

  **Incoming (from client):**
  - `start_download` - Start download with model_id
  - `cancel_download` - Cancel active download by download_id
  - `get_progress` - Get progress for specific download_id
  - `list_registry` - List registry models (optional category filter)

  **Outgoing (to client):**
  - `download_started` - Download initiated with download_id and metadata
  - `progress_update` - Real-time progress (percentage, bytes, speed)
  - `download_complete` - Download finished successfully
  - `download_failed` - Download failed with error details
  - `registry_data` - Registry models list response
  """

  use LeaxerCoreWeb, :channel
  require Logger

  alias LeaxerCore.Models.{DownloadManager, Registry}

  @pubsub LeaxerCore.PubSub
  @topic "downloads:progress"

  @impl true
  def join("downloads:lobby", _payload, socket) do
    Logger.info("Client joined downloads:lobby")

    # Subscribe to download progress broadcasts
    Phoenix.PubSub.subscribe(@pubsub, @topic)

    {:ok, socket}
  end

  @impl true
  def join(_topic, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  # Handle download progress broadcasts from DownloadManager
  @impl true
  def handle_info({:download_started, payload}, socket) do
    push(socket, "download_started", payload)
    {:noreply, socket}
  end

  def handle_info({:progress_update, payload}, socket) do
    push(socket, "progress_update", payload)
    {:noreply, socket}
  end

  def handle_info({:download_complete, payload}, socket) do
    push(socket, "download_complete", payload)
    {:noreply, socket}
  end

  def handle_info({:download_failed, payload}, socket) do
    push(socket, "download_failed", payload)
    {:noreply, socket}
  end

  def handle_info({:download_cancelled, payload}, socket) do
    push(socket, "download_cancelled", payload)
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Handle start_download request from client
  @impl true
  def handle_in("start_download", %{"model_id" => model_id}, socket) do
    Logger.info("Starting download for model: #{model_id}")

    case DownloadManager.start_download(model_id) do
      {:ok, download_id} ->
        {:reply, {:ok, %{download_id: download_id, message: "Download started"}}, socket}

      {:error, reason} ->
        Logger.error("Failed to start download: #{inspect(reason)}")
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle cancel_download request from client
  def handle_in("cancel_download", %{"download_id" => download_id}, socket) do
    Logger.info("Cancelling download: #{download_id}")

    case DownloadManager.cancel_download(download_id) do
      :ok ->
        {:reply, {:ok, %{message: "Download cancelled"}}, socket}

      {:error, reason} ->
        Logger.error("Failed to cancel download: #{inspect(reason)}")
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle get_progress request from client
  def handle_in("get_progress", %{"download_id" => download_id}, socket) do
    case DownloadManager.get_progress(download_id) do
      {:ok, progress} ->
        {:reply, {:ok, progress}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle list_registry request from client
  def handle_in("list_registry", payload, socket) do
    category = Map.get(payload, "category")

    result =
      if category do
        Logger.info("Fetching registry for category: #{category}")
        Registry.get_by_category(category)
      else
        Logger.info("Fetching full registry")
        Registry.get_all()
      end

    case result do
      {:ok, data} ->
        {:reply, {:ok, %{registry: data}}, socket}

      {:error, reason} ->
        Logger.error("Failed to fetch registry: #{inspect(reason)}")
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle unknown events
  def handle_in(event, payload, socket) do
    Logger.warning("Unknown event: #{event}, payload: #{inspect(payload)}")
    {:reply, {:error, %{reason: "unknown_event", event: event}}, socket}
  end
end
