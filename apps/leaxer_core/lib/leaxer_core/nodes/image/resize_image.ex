defmodule LeaxerCore.Nodes.Image.ResizeImage do
  @moduledoc """
  Resize image with presets or custom dimensions.

  Essential for social media prep - "make this Instagram-ready".
  Includes common presets like Instagram Square (1080x1080), Portrait (1080x1350),
  Story (1080x1920), and YouTube (1920x1080).

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> ResizeImage.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "preset" => "instagram_square"}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "ResizeImage"

  @impl true
  def label, do: "Resize Image"

  @impl true
  def category, do: "Image/Transform"

  @impl true
  def description, do: "Resize image with presets or custom dimensions"

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
        default: "preset",
        options: [
          %{value: "preset", label: "Preset"},
          %{value: "custom", label: "Custom"}
        ],
        description: "Use preset or custom dimensions"
      },
      preset: %{
        type: :enum,
        label: "PRESET",
        default: "instagram_square",
        options: [
          %{value: "instagram_square", label: "Instagram Square (1:1)"},
          %{value: "instagram_portrait", label: "Instagram Portrait (4:5)"},
          %{value: "instagram_story", label: "Instagram Story (9:16)"},
          %{value: "youtube", label: "YouTube (16:9)"},
          %{value: "twitter_post", label: "Twitter Post (16:9)"},
          %{value: "facebook_post", label: "Facebook Post (1.91:1)"}
        ],
        description: "Social media size preset"
      },
      width: %{
        type: :integer,
        label: "WIDTH",
        default: 1024,
        optional: true,
        description: "Custom width in pixels"
      },
      height: %{
        type: :integer,
        label: "HEIGHT",
        default: 1024,
        optional: true,
        description: "Custom height in pixels"
      },
      maintain_aspect: %{
        type: :boolean,
        label: "MAINTAIN ASPECT",
        default: true,
        optional: true,
        description: "Keep original aspect ratio"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Resized image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    mode = inputs["mode"] || config["mode"] || "preset"
    preset = inputs["preset"] || config["preset"] || "instagram_square"
    width = inputs["width"] || config["width"] || 1024
    height = inputs["height"] || config["height"] || 1024
    maintain_aspect = inputs["maintain_aspect"] || config["maintain_aspect"] || true

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      {target_width, target_height} =
        case mode do
          "preset" -> get_preset_dimensions(preset)
          "custom" -> {width, height}
          _ -> {1024, 1024}
        end

      resize_image(image, target_width, target_height, maintain_aspect)
    end
  rescue
    e ->
      Logger.error("ResizeImage exception: #{inspect(e)}")
      {:error, "Failed to resize image: #{Exception.message(e)}"}
  end

  defp get_preset_dimensions(preset) do
    case preset do
      "instagram_square" -> {1080, 1080}
      "instagram_portrait" -> {1080, 1350}
      "instagram_story" -> {1080, 1920}
      "youtube" -> {1920, 1080}
      "twitter_post" -> {1200, 675}
      "facebook_post" -> {1200, 630}
      _ -> {1024, 1024}
    end
  end

  defp resize_image(image, width, height, maintain_aspect) do
    case Vips.resize(image, width, height, maintain_aspect: maintain_aspect) do
      {:ok, result} ->
        {:ok, %{"image" => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
