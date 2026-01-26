defmodule LeaxerCore.Nodes.Image.ImageGrid do
  @moduledoc """
  Create NxM grid from multiple images.

  Essential for "show me all 9 variations in one image" - comparison sheets.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> ImageGrid.process(%{"images" => [%{"data" => "...", "mime_type" => "image/png"}, %{"data" => "...", "mime_type" => "image/png"}], "columns" => 2}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "ImageGrid"

  @impl true
  def label, do: "Image Grid"

  @impl true
  def category, do: "Image/Composite"

  @impl true
  def description, do: "Create NxM grid from multiple images"

  @impl true
  def input_spec do
    %{
      images: %{
        type: {:list, :image},
        label: "IMAGES",
        description: "List of images to arrange in grid"
      },
      columns: %{
        type: :integer,
        label: "COLUMNS",
        default: 3,
        min: 1,
        max: 10,
        description: "Number of columns"
      },
      spacing: %{
        type: :integer,
        label: "SPACING",
        default: 10,
        optional: true,
        description: "Spacing between images in pixels"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Grid image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    images = inputs["images"] || config["images"] || []
    columns = inputs["columns"] || config["columns"] || 3
    spacing = inputs["spacing"] || config["spacing"] || 10

    if images == [] or not is_list(images) do
      {:error, "Images list is required and must not be empty"}
    else
      create_grid(images, columns, spacing)
    end
  rescue
    e ->
      Logger.error("ImageGrid exception: #{inspect(e)}")
      {:error, "Failed to create grid: #{Exception.message(e)}"}
  end

  defp create_grid(images, columns, spacing) do
    case Vips.montage(images, columns: columns, shim: spacing) do
      {:ok, result} ->
        {:ok, %{"image" => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
