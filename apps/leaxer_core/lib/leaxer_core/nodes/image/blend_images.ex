defmodule LeaxerCore.Nodes.Image.BlendImages do
  @moduledoc """
  Blend two images with opacity and modes.

  Create composites without external tools.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> BlendImages.process(%{"image_a" => %{"data" => "...", "mime_type" => "image/png"}, "image_b" => %{"data" => "...", "mime_type" => "image/png"}, "mode" => "over", "opacity" => 0.5}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "BlendImages"

  @impl true
  def label, do: "Blend Images"

  @impl true
  def category, do: "Image/Color"

  @impl true
  def description, do: "Blend two images with opacity and modes"

  @impl true
  def input_spec do
    %{
      image_a: %{
        type: :image,
        label: "IMAGE",
        description: "Base image"
      },
      image_b: %{
        type: :image,
        label: "IMAGE",
        description: "Image to blend on top"
      },
      mode: %{
        type: :enum,
        label: "MODE",
        default: "over",
        options: [
          %{value: "over", label: "Over"},
          %{value: "multiply", label: "Multiply"},
          %{value: "screen", label: "Screen"},
          %{value: "overlay", label: "Overlay"},
          %{value: "add", label: "Add"}
        ],
        description: "Blending mode"
      },
      opacity: %{
        type: :float,
        label: "OPACITY",
        default: 0.5,
        min: 0.0,
        max: 1.0,
        step: 0.1,
        description: "Overlay opacity (0-1)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Blended image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image_a = inputs["image_a"] || config["image_a"]
    image_b = inputs["image_b"] || config["image_b"]
    mode = inputs["mode"] || config["mode"] || "over"
    opacity = inputs["opacity"] || config["opacity"] || 0.5

    if is_nil(image_a) or is_nil(image_b) do
      {:error, "Both image_a and image_b are required"}
    else
      blend_images(image_a, image_b, mode, opacity)
    end
  rescue
    e ->
      Logger.error("BlendImages exception: #{inspect(e)}")
      {:error, "Failed to blend images: #{Exception.message(e)}"}
  end

  defp blend_images(base, overlay, mode, opacity) do
    # Convert mode string to atom
    vips_mode =
      case mode do
        "over" -> :over
        "multiply" -> :multiply
        "screen" -> :screen
        "overlay" -> :overlay
        "add" -> :add
        _ -> :over
      end

    # For opacity < 1.0, we need to adjust the overlay's alpha first
    # vips doesn't have a built-in opacity adjustment in composite
    # so we use ifthenelse with blend for smooth opacity control
    if opacity < 1.0 do
      # Create a simple blend using ifthenelse
      # This gives us opacity control - mask determines blend ratio
      case Vips.identify(overlay) do
        {:ok, %{width: w, height: h}} ->
          # Create a gray mask at the opacity level (0-255)
          gray_value = round(opacity * 255)

          case Vips.create_canvas(w, h, color: "#{gray_value}") do
            {:ok, mask} ->
              Vips.ifthenelse(mask, overlay, base)

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Full opacity, use normal composite
      case Vips.composite(base, overlay, mode: vips_mode) do
        {:ok, result} ->
          {:ok, %{"image" => result}}

        {:error, reason} ->
          {:error, reason}
      end
    end
    |> case do
      {:ok, %{data: _, mime_type: _} = result} ->
        {:ok, %{"image" => result}}

      {:ok, %{"image" => _} = result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  end
end
