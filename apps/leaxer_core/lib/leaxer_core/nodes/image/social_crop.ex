defmodule LeaxerCore.Nodes.Image.SocialCrop do
  @moduledoc """
  Crop images to social media aspect ratios.

  Presets: Instagram Square (1:1), Portrait (4:5), Story (9:16), TikTok (9:16), YouTube (16:9), etc.
  Center-crops to target aspect ratio.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> SocialCrop.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "preset" => "Instagram Square 1:1"}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @presets %{
    "Instagram Square 1:1" => {1, 1},
    "Instagram Portrait 4:5" => {4, 5},
    "Instagram Story 9:16" => {9, 16},
    "TikTok 9:16" => {9, 16},
    "YouTube 16:9" => {16, 9},
    "Twitter 16:9" => {16, 9},
    "Facebook 1.91:1" => {191, 100}
  }

  @impl true
  def type, do: "SocialCrop"

  @impl true
  def label, do: "Social Media Crop"

  @impl true
  def category, do: "Image/Composite"

  @impl true
  def description, do: "Crop to social media aspect ratios (Instagram, TikTok, YouTube, etc.)"

  @impl true
  def input_spec do
    preset_options =
      @presets
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn name -> %{value: name, label: name} end)

    %{
      image: %{
        type: :image,
        label: "IMAGE"
      },
      preset: %{
        type: :enum,
        label: "PRESET",
        default: "Instagram Square 1:1",
        options: preset_options
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    preset = inputs["preset"] || config["preset"] || "Instagram Square 1:1"

    if is_nil(image) do
      {:error, "No image provided"}
    else
      crop_to_preset(image, preset)
    end
  rescue
    e ->
      Logger.error("SocialCrop exception: #{inspect(e)}")
      {:error, "Failed to crop image: #{Exception.message(e)}"}
  end

  defp crop_to_preset(image, preset) do
    {target_w, target_h} = Map.get(@presets, preset, {1, 1})

    # Get current dimensions
    case Vips.identify(image) do
      {:ok, %{width: width, height: height}} ->
        # Calculate crop dimensions
        current_ratio = width / height
        target_ratio = target_w / target_h

        {new_width, new_height, left, top} =
          if current_ratio > target_ratio do
            # Too wide, crop width
            new_width = trunc(height * target_ratio)
            new_height = height
            left = div(width - new_width, 2)
            {new_width, new_height, left, 0}
          else
            # Too tall, crop height
            new_width = width
            new_height = trunc(width / target_ratio)
            top = div(height - new_height, 2)
            {new_width, new_height, 0, top}
          end

        Logger.info("SocialCrop: #{width}x#{height} -> #{new_width}x#{new_height} (#{preset})")

        # Crop using vips
        case Vips.crop(image, left, top, new_width, new_height) do
          {:ok, result} ->
            {:ok, %{"image" => result}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
