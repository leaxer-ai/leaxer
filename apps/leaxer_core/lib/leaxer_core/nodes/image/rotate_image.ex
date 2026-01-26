defmodule LeaxerCore.Nodes.Image.RotateImage do
  @moduledoc """
  Rotate image by angle.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> RotateImage.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "angle" => "90"}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "RotateImage"

  @impl true
  def label, do: "Rotate Image"

  @impl true
  def category, do: "Image/Transform"

  @impl true
  def description, do: "Rotate image by angle"

  @impl true
  def input_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image"
      },
      angle: %{
        type: :enum,
        label: "ANGLE",
        default: "90",
        options: [
          %{value: "90", label: "90°"},
          %{value: "180", label: "180°"},
          %{value: "270", label: "270°"},
          %{value: "custom", label: "Custom"}
        ],
        description: "Rotation angle"
      },
      degrees: %{
        type: :float,
        label: "DEGREES",
        default: 0.0,
        optional: true,
        description: "Custom rotation in degrees (if angle is 'custom')"
      },
      background: %{
        type: :string,
        label: "BACKGROUND",
        default: "0 0 0",
        optional: true,
        description: "Background color for empty areas (R G B format)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Rotated image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    angle = inputs["angle"] || config["angle"] || "90"
    degrees = inputs["degrees"] || config["degrees"] || 0.0
    background = inputs["background"] || config["background"] || "0 0 0"

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      rotation_degrees =
        case angle do
          "90" -> 90
          "180" -> 180
          "270" -> 270
          "custom" -> degrees
          _ -> 0
        end

      rotate_image(image, rotation_degrees, background)
    end
  rescue
    e ->
      Logger.error("RotateImage exception: #{inspect(e)}")
      {:error, "Failed to rotate image: #{Exception.message(e)}"}
  end

  defp rotate_image(image, degrees, _background) when degrees in [90, 180, 270] do
    # Use fast rotation for 90-degree increments
    case Vips.rotate(image, degrees) do
      {:ok, result} ->
        {:ok, %{"image" => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rotate_image(image, degrees, background) do
    # Use arbitrary angle rotation for non-90-degree angles
    case Vips.rotate_arbitrary(image, degrees, background: background) do
      {:ok, result} ->
        {:ok, %{"image" => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
