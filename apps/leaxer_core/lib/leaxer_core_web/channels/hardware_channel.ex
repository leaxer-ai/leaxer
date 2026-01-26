defmodule LeaxerCoreWeb.HardwareChannel do
  @moduledoc """
  WebSocket channel for hardware monitoring.
  Streams CPU, GPU, RAM, and VRAM usage stats to connected clients.
  """
  use LeaxerCoreWeb, :channel
  require Logger

  @impl true
  def join("hardware:stats", _payload, socket) do
    Logger.info("Client joined hardware:stats channel")

    # Subscribe to hardware stats updates
    Phoenix.PubSub.subscribe(LeaxerCore.PubSub, "hardware:stats")

    # Send initial stats immediately
    send(self(), :send_initial_stats)

    {:ok, socket}
  end

  @impl true
  def handle_info(:send_initial_stats, socket) do
    stats = LeaxerCore.HardwareMonitor.get_stats()
    push(socket, "hardware_stats", stats)
    {:noreply, socket}
  end

  # Forward hardware stats to the client
  @impl true
  def handle_info({:hardware_stats, stats}, socket) do
    push(socket, "hardware_stats", stats)
    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("[HardwareChannel] Unhandled message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # Client can request stats manually
  @impl true
  def handle_in("get_stats", _payload, socket) do
    stats = LeaxerCore.HardwareMonitor.get_stats()
    {:reply, {:ok, stats}, socket}
  end
end
