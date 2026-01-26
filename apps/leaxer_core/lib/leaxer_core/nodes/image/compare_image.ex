defmodule LeaxerCore.Nodes.Image.CompareImage do
  @moduledoc """
  Interactive before/after image comparison with slider.

  This node provides a visual comparison interface for two images,
  allowing users to see differences by hovering over the node.

  Accepts both base64 and path-based inputs.
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Image

  @impl true
  def type, do: "CompareImage"

  @impl true
  def label, do: "Compare Image"

  @impl true
  def category, do: "Image/Analysis"

  @impl true
  def description, do: "Interactive before/after image comparison with slider"

  @impl true
  def input_spec do
    %{
      before: %{
        type: :image,
        label: "BEFORE",
        description: "The 'before' image (left side)"
      },
      after: %{
        type: :image,
        label: "AFTER",
        description: "The 'after' image (right side)"
      }
    }
  end

  @impl true
  def output_spec do
    %{}
  end

  @impl true
  def ui_component, do: {:custom, "CompareImageNode"}

  @impl true
  def process(inputs, _config) do
    before_image = inputs["before"]
    after_image = inputs["after"]

    # Use Image.to_display_url which handles both base64 and path-based formats
    # Returns {:ok, url} or {:error, reason}
    before_url =
      case before_image do
        nil ->
          nil

        img ->
          case Image.to_display_url(img) do
            {:ok, url} -> url
            _ -> nil
          end
      end

    after_url =
      case after_image do
        nil ->
          nil

        img ->
          case Image.to_display_url(img) do
            {:ok, url} -> url
            _ -> nil
          end
      end

    # Return URLs for frontend rendering (frontend maps these to _before_url/_after_url)
    result = %{}
    result = if before_url, do: Map.put(result, "before_url", before_url), else: result
    result = if after_url, do: Map.put(result, "after_url", after_url), else: result

    {:ok, result}
  rescue
    e ->
      Logger.error("CompareImage exception: #{inspect(e)}")
      {:error, "Failed to process images: #{Exception.message(e)}"}
  end
end
