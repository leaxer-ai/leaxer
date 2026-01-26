defmodule LeaxerCoreWeb.PathsController do
  @moduledoc """
  REST API controller for user data paths.

  Provides endpoints for the frontend to discover user directories
  and manage settings.
  """
  use LeaxerCoreWeb, :controller

  @doc """
  GET /api/paths

  Returns all user data paths.
  """
  def index(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(LeaxerCore.Paths.all_paths())
  end
end
