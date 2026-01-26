defmodule LeaxerCore.Nodes.Image.AddBorder do
  @moduledoc """
  Add colored borders/frames to images.

  Simple colored borders with customizable width and color.
  Useful for framing final outputs.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> AddBorder.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "border_width" => 10, "color" => "WHITE"}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @color_map %{
    "WHITE" => "#FFFFFF",
    "BLACK" => "#000000",
    "GRAY" => "#808080",
    "RED" => "#FF0000",
    "BLUE" => "#0000FF",
    "GREEN" => "#00FF00"
  }

  @impl true
  def type, do: "AddBorder"

  @impl true
  def label, do: "Add Border"

  @impl true
  def category, do: "Image/Effects"

  @impl true
  def description, do: "Add colored border or frame to image"

  @impl true
  def input_spec do
    color_options =
      @color_map
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn color -> %{value: color, label: color} end)

    %{
      image: %{
        type: :image,
        label: "IMAGE"
      },
      border_width: %{
        type: :integer,
        label: "BORDER WIDTH",
        default: 10,
        min: 1,
        max: 100,
        step: 1
      },
      color: %{
        type: :enum,
        label: "COLOR",
        default: "WHITE",
        options: color_options
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
    border_width = inputs["border_width"] || config["border_width"] || 10
    color = inputs["color"] || config["color"] || "WHITE"

    if is_nil(image) do
      {:error, "No image provided"}
    else
      add_border(image, border_width, color)
    end
  rescue
    e ->
      Logger.error("AddBorder exception: #{inspect(e)}")
      {:error, "Failed to add border: #{Exception.message(e)}"}
  end

  defp add_border(image, border_width, color) do
    # Get color hex code
    color_hex = Map.get(@color_map, color, "#FFFFFF")

    case Vips.add_border(image, border_width, color: color_hex) do
      {:ok, result} ->
        Logger.info("AddBorder: #{border_width}px #{color}")
        {:ok, %{"image" => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
