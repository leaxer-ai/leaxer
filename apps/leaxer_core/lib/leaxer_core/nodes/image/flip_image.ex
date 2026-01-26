defmodule LeaxerCore.Nodes.Image.FlipImage do
  @moduledoc """
  Mirror image horizontally or vertically.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> FlipImage.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "direction" => "horizontal"}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "FlipImage"

  @impl true
  def label, do: "Flip Image"

  @impl true
  def category, do: "Image/Transform"

  @impl true
  def description, do: "Mirror image horizontally or vertically"

  @impl true
  def input_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image"
      },
      direction: %{
        type: :enum,
        label: "DIRECTION",
        default: "horizontal",
        options: [
          %{value: "horizontal", label: "Horizontal"},
          %{value: "vertical", label: "Vertical"}
        ],
        description: "Flip direction"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Flipped image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    direction = inputs["direction"] || config["direction"] || "horizontal"

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      flip_image(image, direction)
    end
  rescue
    e ->
      Logger.error("FlipImage exception: #{inspect(e)}")
      {:error, "Failed to flip image: #{Exception.message(e)}"}
  end

  defp flip_image(image, direction) do
    vips_direction =
      case direction do
        "horizontal" -> :horizontal
        "vertical" -> :vertical
        _ -> :horizontal
      end

    case Vips.flip(image, vips_direction) do
      {:ok, result} ->
        {:ok, %{"image" => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
