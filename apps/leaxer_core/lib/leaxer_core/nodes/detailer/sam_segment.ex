defmodule LeaxerCore.Nodes.Detailer.SAMSegment do
  @moduledoc """
  Create precise pixel masks from detected segments using SAM.

  Takes SEGS (segments with bounding boxes) and generates pixel-perfect masks
  for each segment. These masks can be used for:
  - Inpainting/outpainting
  - Compositing
  - Selective image editing
  - Video rotoscoping

  Accepts both base64 and path-based image inputs.

  ## Inputs
  - `image` - Source image
  - `segs` - Segments from DetectObjects (with bounding boxes)
  - `sam_model` - Loaded SAM model from SAMLoader

  ## Outputs
  - `segs` - Segments with added mask paths
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Vips

  @impl true
  def type, do: "SAMSegment"

  @impl true
  def label, do: "SAM Segment"

  @impl true
  def category, do: "Inference/Segmentation"

  @impl true
  def description do
    "Create precise pixel masks from detected segments using SAM"
  end

  @impl true
  def input_spec do
    %{
      image: %{type: :image, label: "IMAGE"},
      segs: %{type: :segs, label: "SEGS"},
      sam_model: %{type: :sam_model, label: "SAM_MODEL"}
    }
  end

  @impl true
  def output_spec do
    %{
      segs: %{type: :segs, label: "SEGS"}
    }
  end

  @impl true
  def process(inputs, _config) do
    segs = inputs["segs"]
    sam_model = inputs["sam_model"]

    # Use explicit image input, or fall back to image embedded in SEGS
    image = inputs["image"] || extract_segs_image(segs)

    with :ok <- validate_image(image),
         :ok <- validate_segs(segs),
         :ok <- validate_sam_model(sam_model) do
      # Materialize image to temp file if base64
      case Vips.materialize_to_temp(image) do
        {:ok, image_path} ->
          model_name = sam_model["model_name"] || "mobile_sam"

          result =
            case LeaxerCore.SAM.process_segs(image_path, segs, model: model_name) do
              {:ok, updated_segs} ->
                # Store original image in segs for downstream nodes
                updated_segs = Map.put(updated_segs, "image", image)
                {:ok, %{"segs" => updated_segs}}

              {:error, reason} ->
                {:error, reason}
            end

          # Clean up temp file if input was base64
          unless is_path_based?(image), do: File.rm(image_path)

          result

        {:error, reason} ->
          {:error, "Failed to process image: #{reason}"}
      end
    end
  end

  defp is_path_based?(%{path: _}), do: true
  defp is_path_based?(%{"path" => _}), do: true
  defp is_path_based?(_), do: false

  # Extract image from SEGS (new format uses "image", legacy uses "image_path")
  defp extract_segs_image(%{"image" => image}), do: image
  defp extract_segs_image(%{"image_path" => path}) when is_binary(path), do: %{path: path}
  defp extract_segs_image(_), do: nil

  defp validate_image(nil), do: {:error, "Image is required"}
  defp validate_image(%{data: _, mime_type: _}), do: :ok
  defp validate_image(%{"data" => _, "mime_type" => _}), do: :ok

  defp validate_image(%{path: path}) when is_binary(path) do
    if File.exists?(path), do: :ok, else: {:error, "Image not found: #{path}"}
  end

  defp validate_image(%{"path" => path}) when is_binary(path) do
    if File.exists?(path), do: :ok, else: {:error, "Image not found: #{path}"}
  end

  defp validate_image(_), do: {:error, "Invalid image input"}

  defp validate_segs(nil), do: {:error, "SEGS is required"}
  defp validate_segs(%{"segments" => _}), do: :ok
  defp validate_segs(_), do: {:error, "Invalid SEGS format"}

  defp validate_sam_model(nil), do: {:error, "SAM model is required"}
  defp validate_sam_model(%{"type" => "sam"}), do: :ok
  defp validate_sam_model(_), do: {:error, "Invalid SAM model type"}
end
