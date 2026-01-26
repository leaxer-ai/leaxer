defmodule LeaxerCoreWeb.UserSocket do
  use Phoenix.Socket

  channel "downloads:*", LeaxerCoreWeb.DownloadChannel
  channel "graph:*", LeaxerCoreWeb.GraphChannel
  channel "logs:*", LeaxerCoreWeb.LogChannel
  channel "hardware:*", LeaxerCoreWeb.HardwareChannel
  channel "chat:*", LeaxerCoreWeb.ChatChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
