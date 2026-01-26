defmodule LeaxerCore.Nodes.Detailer.DetectObjects do
  @moduledoc """
  Detect objects in an image using a text prompt.

  This node uses GroundingDINO to find objects described by your text prompt.
  You can detect anything describable in natural language:
  - "face" - detect faces
  - "hand" - detect hands
  - "person walking" - detect people who are walking
  - "red car, blue car" - detect red and blue cars
  - "text, logo" - detect text and logos

  Accepts both base64 and path-based inputs.

  ## Inputs
  - `image` - Input image to analyze
  - `detector` - Loaded GroundingDINO model from GroundingDinoLoader
  - `prompt` - Text description of objects to detect (comma-separated for multiple)
  - `threshold` - Confidence threshold (higher = fewer but more confident detections)

  ## Outputs
  - `segs` - Detected segments with bounding boxes (for use with SAM or other nodes)
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Vips

  @impl true
  def type, do: "DetectObjects"

  @impl true
  def label, do: "Detect Objects"

  @impl true
  def category, do: "Inference/Detection"

  @impl true
  def description do
    "Detect objects in an image using a text prompt (e.g., 'face', 'hand', 'person')"
  end

  @impl true
  def input_spec do
    %{
      image: %{type: :image, label: "IMAGE"},
      detector: %{type: :detector, label: "DETECTOR"},
      prompt: %{
        type: :string,
        label: "PROMPT",
        default: "face",
        description: "What to detect (e.g., 'face, hand' or 'person walking')"
      },
      box_threshold: %{
        type: :float,
        label: "BOX THRESHOLD",
        default: 0.35,
        min: 0.1,
        max: 1.0,
        step: 0.05,
        description: "Bounding box confidence threshold"
      },
      text_threshold: %{
        type: :float,
        label: "TEXT THRESHOLD",
        default: 0.25,
        min: 0.1,
        max: 1.0,
        step: 0.05,
        description: "Text matching confidence threshold"
      },
      padding: %{
        type: :integer,
        label: "PADDING",
        default: 32,
        min: 0,
        max: 256,
        step: 8,
        description: "Padding around detected regions (pixels)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      segs: %{type: :segs, label: "SEGS"}
    }
  end

  require Logger

  @impl true
  def process(inputs, config) do
    # inputs = values from connected edges (image, detector)
    # config = node's configured data (prompt, thresholds, etc.) merged with exec config
    image = inputs["image"]
    detector = inputs["detector"]

    # Read from config (node data), not inputs (edge connections)
    prompt = config["prompt"] || "face"
    box_threshold = config["box_threshold"] || config["threshold"] || 0.35
    text_threshold = config["text_threshold"] || 0.25
    padding = config["padding"] || 32

    Logger.info(
      "[DetectObjects] prompt=#{inspect(prompt)}, box_threshold=#{box_threshold}, text_threshold=#{text_threshold}"
    )

    # Validate inputs
    with :ok <- validate_image(image),
         :ok <- validate_detector(detector) do
      # Materialize image to temp file if it's base64
      case Vips.materialize_to_temp(image) do
        {:ok, image_path} ->
          result =
            run_detection(image_path, image, prompt, box_threshold, text_threshold, padding)

          # Clean up temp file if input was base64
          unless is_path_based?(image), do: File.rm(image_path)

          result

        {:error, reason} ->
          {:error, "Failed to process image: #{reason}"}
      end
    end
  end

  defp run_detection(image_path, original_image, prompt, box_threshold, text_threshold, padding) do
    case LeaxerCore.GroundingDino.detect(image_path, prompt,
           threshold: box_threshold,
           text_threshold: text_threshold
         ) do
      {:ok, result} ->
        # Convert to SEGS format and include source image for downstream nodes
        segs = LeaxerCore.GroundingDino.to_segs(result, padding: padding)
        # Store the original image (base64 or path) for downstream nodes
        segs_with_image = Map.put(segs, "image", original_image)
        {:ok, %{"segs" => segs_with_image}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp is_path_based?(%{path: _}), do: true
  defp is_path_based?(%{"path" => _}), do: true
  defp is_path_based?(_), do: false

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

  defp validate_detector(nil), do: {:error, "Detector is required"}
  defp validate_detector(%{"type" => "grounding_dino"}), do: :ok
  defp validate_detector(_), do: {:error, "Invalid detector type"}
end
