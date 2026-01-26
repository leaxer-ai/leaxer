defmodule LeaxerCore.Nodes.Image.SharpenImage do
  @moduledoc """
  Enhance image details using unsharp mask.

  Essential as SD output often needs sharpening post-generation.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> SharpenImage.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}, "sigma" => 1.0}, %{})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png"}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "SharpenImage"

  @impl true
  def label, do: "Sharpen Image"

  @impl true
  def category, do: "Image/Effects"

  @impl true
  def description, do: "Enhance image details using unsharp mask"

  @impl true
  def input_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image"
      },
      sigma: %{
        type: :float,
        label: "SIGMA",
        default: 1.0,
        description: "Sharpening sigma (0.5-3.0, default 1.0)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Sharpened image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    sigma = inputs["sigma"] || config["sigma"] || inputs["amount"] || config["amount"] || 1.0

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      sharpen_image(image, sigma)
    end
  rescue
    e ->
      Logger.error("SharpenImage exception: #{inspect(e)}")
      {:error, "Failed to sharpen image: #{Exception.message(e)}"}
  end

  defp sharpen_image(image, sigma) do
    case Vips.sharpen(image, sigma: sigma) do
      {:ok, result} ->
        {:ok, %{"image" => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
