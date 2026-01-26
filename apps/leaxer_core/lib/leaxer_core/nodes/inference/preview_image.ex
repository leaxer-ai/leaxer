defmodule LeaxerCore.Nodes.Inference.PreviewImage do
  @moduledoc """
  Preview an image in the workflow.

  This node displays the generated image for visual feedback.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "PreviewImage"

  @impl true
  def label, do: "Preview Image"

  @impl true
  def category, do: "Image/Analysis"

  @impl true
  def description, do: "Display an image for preview"

  @impl true
  def input_spec do
    %{
      image: %{type: :image, label: "IMAGE"}
    }
  end

  @impl true
  def output_spec do
    %{}
  end

  @impl true
  def ui_component, do: {:custom, "PreviewImageNode"}

  @impl true
  def process(inputs, _config) do
    image = inputs["image"]

    # Use the Image helper to get a display URL
    # This handles both base64 data (returns data URL) and path (returns HTTP URL)
    # Base64 mode avoids disk I/O for preview-only images
    case LeaxerCore.Image.to_display_url(image) do
      {:ok, url} ->
        {:ok, %{"preview" => url}}

      {:error, _reason} ->
        # No valid image data
        {:ok, %{}}
    end
  end
end
