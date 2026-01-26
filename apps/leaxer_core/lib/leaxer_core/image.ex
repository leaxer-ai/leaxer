defmodule LeaxerCore.Image do
  @moduledoc """
  Helper module for working with image data in Leaxer workflows.

  ## Image Formats

  Images in Leaxer can be represented in two formats:

  1. **Path-based**: `%{path: "/path/to/image.png", type: :image}`
     - Traditional format where image data is stored on disk
     - Used when image needs to be passed to external tools (sd.cpp, vips, etc.)
     - Frontend fetches via HTTP endpoint

  2. **Base64-based**: `%{data: "base64string...", mime_type: "image/png"}`
     - In-memory format that avoids disk I/O
     - Ideal for preview-only images that don't need to be saved
     - Frontend displays directly via data URL
     - Reduces disk writes and HTTP round-trips

  ## Usage

  Nodes that consume images should use the helper functions in this module
  to handle both formats transparently:

      case LeaxerCore.Image.extract_path_or_materialize(image) do
        {:ok, path} -> # Use path for external tools
        {:error, reason} -> # Handle error
      end

  Nodes that only need to display images (like PreviewImage) can check for
  base64 data first to avoid materialization:

      case LeaxerCore.Image.to_display_url(image) do
        {:ok, url} -> # Use URL (either HTTP path or data URL)
        {:error, reason} -> # Handle error
      end
  """

  require Logger

  @doc """
  Extracts a file path from an image, materializing base64 data to disk if needed.

  This function ensures you always get a file path, even if the image was
  originally in base64 format. Use this when you need to pass the image to
  external tools that require a file path.

  ## Returns

  - `{:ok, path}` - The file path to the image
  - `{:error, reason}` - If the image format is invalid or materialization failed
  """
  @spec extract_path_or_materialize(map()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_path_or_materialize(image) when is_map(image) do
    case extract_path(image) do
      path when is_binary(path) ->
        {:ok, path}

      nil ->
        # Try to materialize base64 data to disk
        case extract_base64_data(image) do
          {data, _mime_type} when is_binary(data) ->
            materialize_base64_to_disk(data)

          nil ->
            {:error, "No image path or data found"}
        end
    end
  end

  def extract_path_or_materialize(_), do: {:error, "Invalid image format"}

  @doc """
  Converts an image to a display URL for the frontend.

  If the image is base64-based, returns a data URL.
  If the image is path-based, returns an HTTP URL.

  This avoids disk I/O when the image is already in base64 format.

  ## Returns

  - `{:ok, url}` - The display URL (data URL or HTTP path)
  - `{:error, reason}` - If the image format is invalid
  """
  @spec to_display_url(map()) :: {:ok, String.t()} | {:error, String.t()}
  def to_display_url(image) when is_map(image) do
    # Check for base64 data first (avoids disk I/O)
    case extract_base64_data(image) do
      {data, mime_type} when is_binary(data) and is_binary(mime_type) ->
        {:ok, "data:#{mime_type};base64,#{data}"}

      nil ->
        # Fall back to path-based URL
        case extract_path(image) do
          path when is_binary(path) ->
            url = path_to_url(path) <> "?t=#{System.system_time(:millisecond)}"
            {:ok, url}

          nil ->
            {:error, "No image path or data found"}
        end
    end
  end

  def to_display_url(_), do: {:error, "Invalid image format"}

  @doc """
  Extracts the file path from an image map.

  Handles both atom and string keys.

  ## Returns

  - The path string if found
  - `nil` if no path is present
  """
  @spec extract_path(map()) :: String.t() | nil
  def extract_path(%{path: p}) when is_binary(p), do: p
  def extract_path(%{"path" => p}) when is_binary(p), do: p
  def extract_path(_), do: nil

  @doc """
  Extracts base64 data and mime type from an image map.

  Handles both atom and string keys.

  ## Returns

  - `{data, mime_type}` tuple if found
  - `nil` if no base64 data is present
  """
  @spec extract_base64_data(map()) :: {String.t(), String.t()} | nil
  def extract_base64_data(image) when is_map(image) do
    data = image[:data] || image["data"]
    mime_type = image[:mime_type] || image["mime_type"]

    if is_binary(data) and is_binary(mime_type) do
      {data, mime_type}
    else
      nil
    end
  end

  def extract_base64_data(_), do: nil

  @doc """
  Checks if an image is in base64 format.
  """
  @spec base64?(map()) :: boolean()
  def base64?(image) when is_map(image), do: extract_base64_data(image) != nil
  def base64?(_), do: false

  @doc """
  Checks if an image is in path format.
  """
  @spec path?(map()) :: boolean()
  def path?(image) when is_map(image), do: extract_path(image) != nil
  def path?(_), do: false

  # Materialize base64 data to a temporary file
  defp materialize_base64_to_disk(base64_data) do
    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        output_dir = LeaxerCore.Paths.tmp_dir()
        File.mkdir_p!(output_dir)

        timestamp = DateTime.utc_now() |> DateTime.to_unix()
        random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
        path = Path.join(output_dir, "materialized_#{timestamp}_#{random}.png")

        case File.write(path, binary_data) do
          :ok ->
            Logger.debug("[Image] Materialized base64 data to #{path}")
            {:ok, path}

          {:error, reason} ->
            {:error, "Failed to write image: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Invalid base64 data"}
    end
  end

  # Convert file path to HTTP URL for browser access
  defp path_to_url(path) do
    outputs_dir = LeaxerCore.Paths.outputs_dir()
    tmp_dir = LeaxerCore.Paths.tmp_dir()
    inputs_dir = LeaxerCore.Paths.inputs_dir()

    cond do
      String.starts_with?(path, tmp_dir) ->
        relative = String.replace_prefix(path, tmp_dir <> "/", "")
        "/api/tmp/#{relative}"

      String.starts_with?(path, outputs_dir) ->
        relative = String.replace_prefix(path, outputs_dir <> "/", "")
        "/api/outputs/#{relative}"

      String.starts_with?(path, inputs_dir) ->
        relative = String.replace_prefix(path, inputs_dir <> "/", "")
        "/api/inputs/#{relative}"

      true ->
        "/api/tmp/#{Path.basename(path)}"
    end
  end
end
