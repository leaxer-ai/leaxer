defmodule LeaxerCoreWeb.Plugs.PrivateNetworkAccess do
  @moduledoc """
  Handles Private Network Access (PNA) preflight requests.

  This is required for Tauri apps where the WebView (tauri.localhost) needs to
  access the local backend (localhost:4000). Modern browsers block these requests
  unless the server responds with the appropriate headers.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Check if this is a PNA preflight request
    if get_req_header(conn, "access-control-request-private-network") == ["true"] do
      conn
      |> put_resp_header("access-control-allow-private-network", "true")
    else
      conn
    end
  end
end
