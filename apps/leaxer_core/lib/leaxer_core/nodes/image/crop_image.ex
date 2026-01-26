defmodule LeaxerCore.Nodes.Image.CropImage do
  @moduledoc """
  Crop image to region (center or manual).

  Essential for fixing compositions without regenerating the image.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> CropImage.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "mode" => "center", "width" => 512, "height" => 512}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "CropImage"

  @impl true
  def label, do: "Crop Image"

  @impl true
  def category, do: "Image/Transform"

  @impl true
  def description, do: "Crop image to region (center or manual)"

  @impl true
  def input_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image"
      },
      mode: %{
        type: :enum,
        label: "MODE",
        default: "center",
        options: [
          %{value: "center", label: "Center"},
          %{value: "manual", label: "Manual"}
        ],
        description: "Crop mode"
      },
      width: %{
        type: :integer,
        label: "WIDTH",
        default: 512,
        description: "Crop width in pixels"
      },
      height: %{
        type: :integer,
        label: "HEIGHT",
        default: 512,
        description: "Crop height in pixels"
      },
      x: %{
        type: :integer,
        label: "X",
        default: 0,
        optional: true,
        description: "X position for manual crop"
      },
      y: %{
        type: :integer,
        label: "Y",
        default: 0,
        optional: true,
        description: "Y position for manual crop"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Cropped image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    mode = inputs["mode"] || config["mode"] || "center"
    width = inputs["width"] || config["width"] || 512
    height = inputs["height"] || config["height"] || 512
    x = inputs["x"] || config["x"] || 0
    y = inputs["y"] || config["y"] || 0

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      crop_image(image, mode, width, height, x, y)
    end
  rescue
    e ->
      Logger.error("CropImage exception: #{inspect(e)}")
      {:error, "Failed to crop image: #{Exception.message(e)}"}
  end

  defp crop_image(image, mode, width, height, x, y) do
    result =
      case mode do
        "center" ->
          Vips.crop_center(image, width, height)

        "manual" ->
          Vips.crop(image, x, y, width, height)

        _ ->
          Vips.crop_center(image, width, height)
      end

    case result do
      {:ok, cropped} ->
        {:ok, %{"image" => cropped}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
