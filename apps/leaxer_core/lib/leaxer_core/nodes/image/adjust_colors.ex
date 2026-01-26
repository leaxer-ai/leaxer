defmodule LeaxerCore.Nodes.Image.AdjustColors do
  @moduledoc """
  Adjust brightness, contrast, and saturation.

  Essential for quick corrections without external editors.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> AdjustColors.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "brightness" => 10, "contrast" => 1.1}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "AdjustColors"

  @impl true
  def label, do: "Adjust Colors"

  @impl true
  def category, do: "Image/Color"

  @impl true
  def description, do: "Adjust brightness, contrast, and saturation"

  @impl true
  def input_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image"
      },
      brightness: %{
        type: :integer,
        label: "BRIGHTNESS",
        default: 0,
        min: -100,
        max: 100,
        description: "Brightness adjustment (-100 to 100)"
      },
      contrast: %{
        type: :float,
        label: "CONTRAST",
        default: 1.0,
        min: 0.5,
        max: 2.0,
        step: 0.1,
        description: "Contrast multiplier (0.5 to 2.0, 1.0 = no change)"
      },
      saturation: %{
        type: :float,
        label: "SATURATION",
        default: 1.0,
        min: 0.0,
        max: 2.0,
        step: 0.1,
        description: "Saturation multiplier (0 = grayscale, 1.0 = no change)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Adjusted image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    brightness = inputs["brightness"] || config["brightness"] || 0
    contrast = inputs["contrast"] || config["contrast"] || 1.0
    saturation = inputs["saturation"] || config["saturation"] || 1.0

    # Handle legacy integer saturation (100 = no change)
    saturation =
      if is_integer(saturation) and saturation > 2 do
        saturation / 100.0
      else
        saturation
      end

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      adjust_colors(image, brightness, contrast, saturation)
    end
  rescue
    e ->
      Logger.error("AdjustColors exception: #{inspect(e)}")
      {:error, "Failed to adjust colors: #{Exception.message(e)}"}
  end

  defp adjust_colors(image, brightness, contrast, saturation) do
    # Apply adjustments in sequence, propagating errors
    with {:ok, img} <- {:ok, image},
         {:ok, img} <- maybe_adjust_brightness_contrast(img, brightness, contrast),
         {:ok, img} <- maybe_adjust_saturation(img, saturation) do
      {:ok, %{"image" => img}}
    end
  end

  defp maybe_adjust_brightness_contrast(img, brightness, contrast) do
    if brightness != 0 or contrast != 1.0 do
      Vips.adjust_brightness_contrast(img, brightness, contrast)
    else
      {:ok, img}
    end
  end

  defp maybe_adjust_saturation(img, saturation) do
    if saturation != 1.0 do
      Vips.adjust_saturation(img, saturation)
    else
      {:ok, img}
    end
  end
end
