defmodule LeaxerCore.Nodes.Image.ImageInfo do
  @moduledoc """
  Extract image metadata (dimensions, format, file size).

  Essential for validation and debugging workflows.

  Accepts both base64 and path-based inputs.

  ## Examples

      iex> ImageInfo.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}}, %{})
      {:ok, %{"width" => 1024, "height" => 1024, "format" => "PNG", "size_mb" => 2.5}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "ImageInfo"

  @impl true
  def label, do: "Image Info"

  @impl true
  def category, do: "Image/Analysis"

  @impl true
  def description, do: "Extract image metadata (dimensions, format, file size)"

  @impl true
  def input_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Image to analyze"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      width: %{
        type: :integer,
        label: "WIDTH",
        description: "Image width in pixels"
      },
      height: %{
        type: :integer,
        label: "HEIGHT",
        description: "Image height in pixels"
      },
      format: %{
        type: :string,
        label: "FORMAT",
        description: "Image format (PNG, JPEG, etc.)"
      },
      size_mb: %{
        type: :float,
        label: "SIZE MB",
        description: "File size in megabytes"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      get_info(image)
    end
  rescue
    e ->
      Logger.error("ImageInfo exception: #{inspect(e)}")
      {:error, "Failed to get image info: #{Exception.message(e)}"}
  end

  defp get_info(image) do
    case Vips.identify(image) do
      {:ok, info} ->
        size_mb = info.size_bytes / (1024 * 1024)

        {:ok,
         %{
           "width" => info.width,
           "height" => info.height,
           "format" => info.format,
           "size_mb" => Float.round(size_mb, 2)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
