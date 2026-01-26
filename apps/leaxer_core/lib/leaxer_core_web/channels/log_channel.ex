defmodule LeaxerCoreWeb.LogChannel do
  @moduledoc """
  WebSocket channel for streaming server logs to frontend clients.
  """
  use LeaxerCoreWeb, :channel

  alias LeaxerCore.LogBroadcaster

  @pubsub LeaxerCore.PubSub
  @topic "logs:stream"

  @impl true
  def join("logs:viewer", _payload, socket) do
    # Subscribe to log broadcasts
    Phoenix.PubSub.subscribe(@pubsub, @topic)

    # Send recent logs to catch up new subscribers
    recent_logs = LogBroadcaster.get_recent_logs(100)

    IO.puts("[LogChannel] Client joined, sending #{length(recent_logs)} recent logs")

    {:ok, %{recent_logs: recent_logs}, socket}
  end

  @impl true
  def handle_info({:log_batch, logs}, socket) do
    push(socket, "log_batch", %{logs: logs})
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_in("clear_logs", _payload, socket) do
    # Client requested log clear (frontend-only operation)
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in(_event, _payload, socket) do
    {:noreply, socket}
  end
end
