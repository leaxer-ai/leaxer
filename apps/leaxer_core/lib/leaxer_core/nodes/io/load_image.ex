defmodule LeaxerCore.Nodes.IO.LoadImage do
  @moduledoc """
  Load an image from a file path.

  Essential for processing local images - takes a file path and outputs
  an image object that can be used by image processing nodes.

  Note: LoadImage returns path-based output since the image is already on disk.
  Downstream nodes accept both path-based and base64 inputs.

  ## Examples

      iex> LoadImage.process(%{}, %{"path" => "/path/to/image.png"})
      {:ok, %{"image" => %{"path" => "/path/to/image.png", "width" => 1024, "height" => 768}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "LoadImage"

  @impl true
  def label, do: "Load Image"

  @impl true
  def category, do: "IO/Image"

  @impl true
  def description, do: "Load an image from a file path"

  @impl true
  def ui_component, do: {:custom, "LoadImageNode"}

  @impl true
  def input_spec do
    %{
      # Path is stored in node data but not rendered as a UI field
      # The custom component handles file selection
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Loaded image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    path = inputs["path"] || config["path"] || ""

    cond do
      path == "" ->
        {:error, "Image path is required - use file picker in UI"}

      !File.exists?(path) ->
        {:error, "Image file not found: #{path}"}

      !is_image_file?(path) ->
        {:error, "File is not a supported image format"}

      true ->
        load_image(path)
    end
  rescue
    e ->
      Logger.error("LoadImage exception: #{inspect(e)}")
      {:error, "Failed to load image: #{Exception.message(e)}"}
  end

  defp is_image_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tiff", ".tif", ".webp"]
  end

  defp load_image(path) do
    # Try to get image info via vips
    case Vips.identify(%{path: path}) do
      {:ok, info} ->
        {:ok,
         %{
           "image" => %{
             "path" => path,
             "width" => info.width,
             "height" => info.height,
             "format" => info.format,
             "size_bytes" => info.size_bytes
           }
         }}

      {:error, _reason} ->
        # Fallback: return basic image info without dimensions
        # This allows the node to work even without vips
        Logger.warning("vips not available, loading image without dimension info: #{path}")
        ext = Path.extname(path) |> String.trim_leading(".") |> String.upcase()

        size =
          case File.stat(path) do
            {:ok, %{size: s}} -> s
            _ -> 0
          end

        {:ok,
         %{
           "image" => %{
             "path" => path,
             "width" => nil,
             "height" => nil,
             "format" => ext,
             "size_bytes" => size
           }
         }}
    end
  end
end
