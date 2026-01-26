defmodule LeaxerCoreWeb.UploadController do
  @moduledoc """
  Handles file uploads for images and other input files.
  """
  use LeaxerCoreWeb, :controller

  alias LeaxerCore.Paths

  # Allowed image extensions
  @allowed_extensions [".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif"]

  # Common image MIME types
  @content_types %{
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".bmp" => "image/bmp",
    ".tiff" => "image/tiff",
    ".tif" => "image/tiff",
    ".svg" => "image/svg+xml"
  }

  @doc """
  POST /api/upload/image
  Uploads an image file to the inputs directory.
  """
  def upload_image(conn, %{"file" => upload}) do
    with {:ok, ext} <- validate_extension(upload.filename),
         {:ok, dest_path} <- save_file(upload, ext) do
      conn
      |> put_status(:ok)
      |> json(%{
        success: true,
        path: dest_path,
        filename: Path.basename(dest_path),
        url: "/api/inputs/#{Path.basename(dest_path)}"
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  @doc """
  GET /api/inputs/*path
  Serves a file from the inputs directory.
  """
  def show(conn, %{"path" => path_segments}) do
    filename = Path.join(path_segments)
    file_path = Path.join(Paths.inputs_dir(), filename)

    # Security: ensure the resolved path is still within the inputs directory
    resolved = Path.expand(file_path)
    base_expanded = Path.expand(Paths.inputs_dir())

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

  defp validate_extension(filename) do
    ext = Path.extname(filename) |> String.downcase()

    if ext in @allowed_extensions do
      {:ok, ext}
    else
      {:error, "Invalid file type. Allowed: #{Enum.join(@allowed_extensions, ", ")}"}
    end
  end

  defp save_file(upload, ext) do
    # Ensure inputs directory exists
    File.mkdir_p!(Paths.inputs_dir())

    # Generate unique filename using timestamp + random string
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    filename = "#{timestamp}_#{random}#{ext}"
    dest_path = Path.join(Paths.inputs_dir(), filename)

    case File.cp(upload.path, dest_path) do
      :ok -> {:ok, dest_path}
      {:error, reason} -> {:error, "Failed to save file: #{inspect(reason)}"}
    end
  end
end
