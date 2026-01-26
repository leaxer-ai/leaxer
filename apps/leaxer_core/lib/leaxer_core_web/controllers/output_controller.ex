defmodule LeaxerCoreWeb.OutputController do
  @moduledoc """
  Serves generated output files (images, etc.) from the user's outputs directory.
  """
  use LeaxerCoreWeb, :controller

  alias LeaxerCore.Paths

  # Common image MIME types
  @content_types %{
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".bmp" => "image/bmp",
    ".svg" => "image/svg+xml"
  }

  @doc """
  Serves a file from the outputs directory.
  """
  def show(conn, %{"path" => path_segments}) do
    serve_from_dir(conn, path_segments, Paths.outputs_dir())
  end

  @doc """
  Serves a file from the tmp directory (preview images).
  """
  def show_tmp(conn, %{"path" => path_segments}) do
    serve_from_dir(conn, path_segments, Paths.tmp_dir())
  end

  defp serve_from_dir(conn, path_segments, base_dir) do
    filename = Path.join(path_segments)
    file_path = Path.join(base_dir, filename)

    # Security: ensure the resolved path is still within the base directory
    resolved = Path.expand(file_path)
    base_expanded = Path.expand(base_dir)

    if String.starts_with?(resolved, base_expanded) and File.exists?(resolved) do
      ext = Path.extname(filename) |> String.downcase()
      content_type = Map.get(@content_types, ext, "application/octet-stream")

      conn
      |> put_resp_content_type(content_type)
      |> send_file(200, resolved)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "File not found"})
    end
  end
end
