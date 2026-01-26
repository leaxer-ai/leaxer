defmodule LeaxerCore.Nodes.Image.WatermarkImage do
  @moduledoc """
  Add text watermark with position and opacity.

  Artists NEED this before sharing portfolios publicly.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> WatermarkImage.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "watermark_text" => "@myhandle", "position" => "bottom_right"}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "WatermarkImage"

  @impl true
  def label, do: "Watermark Image"

  @impl true
  def category, do: "Image/Effects"

  @impl true
  def description, do: "Add text watermark with position and opacity"

  @impl true
  def input_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image"
      },
      watermark_text: %{
        type: :string,
        label: "WATERMARK TEXT",
        default: "",
        optional: true,
        description: "Text to use as watermark"
      },
      position: %{
        type: :enum,
        label: "POSITION",
        default: "bottom_right",
        options: [
          %{value: "center", label: "Center"},
          %{value: "top_left", label: "Top Left"},
          %{value: "top_right", label: "Top Right"},
          %{value: "bottom_left", label: "Bottom Left"},
          %{value: "bottom_right", label: "Bottom Right"}
        ],
        description: "Watermark position"
      },
      opacity: %{
        type: :float,
        label: "OPACITY",
        default: 0.5,
        min: 0.0,
        max: 1.0,
        step: 0.1,
        description: "Watermark opacity (0-1)"
      },
      font_size: %{
        type: :integer,
        label: "FONT SIZE",
        default: 32,
        optional: true,
        description: "Text size in pixels"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Watermarked image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    watermark_text = inputs["watermark_text"] || config["watermark_text"] || ""
    position = inputs["position"] || config["position"] || "bottom_right"
    opacity = inputs["opacity"] || config["opacity"] || 0.5
    font_size = inputs["font_size"] || config["font_size"] || 32

    cond do
      is_nil(image) ->
        {:error, "Image input is required"}

      watermark_text == "" ->
        {:error, "Watermark text is required"}

      true ->
        add_watermark(image, watermark_text, position, opacity, font_size)
    end
  rescue
    e ->
      Logger.error("WatermarkImage exception: #{inspect(e)}")
      {:error, "Failed to add watermark: #{Exception.message(e)}"}
  end

  defp add_watermark(image, text, position, opacity, font_size) do
    # Get image dimensions to calculate position
    case Vips.identify(image) do
      {:ok, %{width: img_w, height: img_h}} ->
        # Create text image
        font = "sans #{font_size}"

        case Vips.text(text, font: font, rgba: true) do
          {:ok, text_image} ->
            # Get text dimensions
            case Vips.identify(text_image) do
              {:ok, %{width: text_w, height: text_h}} ->
                # Calculate position based on gravity
                padding = 10
                {x, y} = calculate_position(position, img_w, img_h, text_w, text_h, padding)

                # Composite text onto image at calculated position with opacity
                # For opacity, we use a gray mask
                gray_value = round(opacity * 255)

                case Vips.create_canvas(text_w, text_h, color: "#{gray_value}") do
                  {:ok, opacity_mask} ->
                    # First, create a transparent canvas the size of the image
                    case Vips.create_canvas(img_w, img_h, color: "0 0 0") do
                      {:ok, canvas} ->
                        # Insert text at position
                        case Vips.insert(canvas, text_image, x, y) do
                          {:ok, positioned_text} ->
                            # Insert opacity mask at same position
                            case Vips.insert(canvas, opacity_mask, x, y) do
                              {:ok, positioned_mask} ->
                                # Blend using mask
                                case Vips.ifthenelse(positioned_mask, positioned_text, image) do
                                  {:ok, result} ->
                                    {:ok, %{"image" => result}}

                                  {:error, reason} ->
                                    {:error, reason}
                                end

                              {:error, reason} ->
                                {:error, reason}
                            end

                          {:error, reason} ->
                            {:error, reason}
                        end

                      {:error, reason} ->
                        {:error, reason}
                    end

                  {:error, reason} ->
                    {:error, reason}
                end

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_position(position, img_w, img_h, text_w, text_h, padding) do
    case position do
      "center" ->
        {div(img_w - text_w, 2), div(img_h - text_h, 2)}

      "top_left" ->
        {padding, padding}

      "top_right" ->
        {img_w - text_w - padding, padding}

      "bottom_left" ->
        {padding, img_h - text_h - padding}

      "bottom_right" ->
        {img_w - text_w - padding, img_h - text_h - padding}

      _ ->
        {img_w - text_w - padding, img_h - text_h - padding}
    end
  end
end
