defmodule LeaxerCoreWeb.HealthController do
  @moduledoc """
  Health check endpoint for startup readiness detection.

  This endpoint is used by the Tauri desktop app to detect when the
  Elixir backend is fully started and ready to accept requests, replacing
  the previous fixed-time sleep approach.
  """

  use LeaxerCoreWeb, :controller

  @doc """
  Health check endpoint that verifies critical services are running.

  Returns 200 with `{"status": "healthy"}` if all checks pass,
  or 503 with `{"status": "unhealthy", "checks": {...}}` if any fail.
  """
  def check(conn, _params) do
    checks = %{
      pubsub: Process.whereis(LeaxerCore.PubSub) != nil,
      queue: Process.whereis(LeaxerCore.Queue) != nil,
      node_registry: Process.whereis(LeaxerCore.Nodes.Registry) != nil
    }

    all_healthy = Enum.all?(checks, fn {_name, status} -> status end)

    if all_healthy do
      json(conn, %{status: "healthy"})
    else
      conn
      |> put_status(503)
      |> json(%{status: "unhealthy", checks: checks})
    end
  end
end
