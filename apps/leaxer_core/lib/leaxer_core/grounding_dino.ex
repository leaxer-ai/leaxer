defmodule LeaxerCore.GroundingDino do
  @moduledoc """
  Wrapper for leaxer-grounding-dino command-line operations.
  Provides interface for GroundingDINO text-prompted object detection using ONNX Runtime.
  """

  alias LeaxerCore.BinaryFinder

  require Logger

  @doc """
  Get the path to the leaxer-grounding-dino binary.
  """
  def bin_path do
    BinaryFinder.priv_bin_path("leaxer-grounding-dino")
  end

  @doc """
  Get the path to the GroundingDINO models directory.
  """
  def models_path do
    Path.join([LeaxerCore.Paths.models_dir(), "grounding_dino"])
  end

  @doc """
  Check if leaxer-grounding-dino is installed and available.
  Returns {:ok, binary_path} if available, {:error, reason} otherwise.
  """
  def check_installation do
    path = bin_path()

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "leaxer-grounding-dino binary not found at #{path}"}
    end
  end

  @doc """
  Check if the model is downloaded and available.
  """
  def check_model(model_name \\ "groundingdino_swint_ogc") do
    model_path = Path.join(models_path(), "#{model_name}.onnx")

    if File.exists?(model_path) do
      {:ok, model_path}
    else
      {:error, "Model not found at #{model_path}. Please download the model first."}
    end
  end

  @doc """
  Get available models with their descriptions.
  """
  def available_models do
    %{
      "groundingdino_swint_ogc" => %{
        label: "GroundingDINO Swin-T",
        size: "350MB",
        description: "Fast, good quality detection (ONNX)",
        download_url:
          "https://github.com/leaxer-ai/leaxer-grounding-dino/releases/download/v0.1.0/groundingdino_swint_ogc.onnx"
      },
      "groundingdino_swinb_cogcoor" => %{
        label: "GroundingDINO Swin-B",
        size: "700MB",
        description: "Slower, better quality detection (ONNX)",
        download_url:
          "https://github.com/leaxer-ai/leaxer-grounding-dino/releases/download/v0.1.0/groundingdino_swinb_cogcoor.onnx"
      }
    }
  end

  @doc """
  Detect objects in an image using a text prompt.

  ## Options
  - `:threshold` - Box confidence threshold (default: 0.35)
  - `:text_threshold` - Text matching threshold (default: 0.25)
  - `:model` - Model name (default: "groundingdino_swint_ogc")

  ## Examples

      iex> detect("input.jpg", "face, hand")
      {:ok, %{
        "detections" => [
          %{"id" => 0, "label" => "face", "confidence" => 0.92, "bbox" => [100, 50, 200, 180]},
          %{"id" => 1, "label" => "hand", "confidence" => 0.85, "bbox" => [300, 200, 380, 320]}
        ]
      }}
  """
  def detect(image_path, prompt, opts \\ []) do
    with {:ok, _} <- check_installation(),
         :ok <- validate_input(image_path) do
      do_detect(image_path, prompt, opts)
    end
  end

  defp validate_input(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "Input file not found: #{path}"}
    end
  end

  defp do_detect(image_path, prompt, opts) do
    threshold = opts[:threshold] || 0.35
    text_threshold = opts[:text_threshold] || 0.25

    # Create temp file for output
    output_path =
      Path.join(System.tmp_dir!(), "gdino_#{:erlang.unique_integer([:positive])}.json")

    args = [
      "detect",
      "--image",
      image_path,
      "--prompt",
      prompt,
      "--threshold",
      to_string(threshold),
      "--text-threshold",
      to_string(text_threshold),
      "--output",
      output_path
    ]

    Logger.info("Running leaxer-grounding-dino: #{bin_path()} #{Enum.join(args, " ")}")

    case System.cmd(bin_path(), args, stderr_to_stdout: true) do
      {_output, exit_code} ->
        # Read and parse the JSON output
        # Note: exit code may be non-zero due to PyInstaller multiprocessing cleanup,
        # but detection can still succeed if output file exists with valid JSON
        case File.read(output_path) do
          {:ok, json} ->
            File.rm(output_path)

            case Jason.decode(json) do
              {:ok, result} ->
                # Check if result contains an error
                if Map.has_key?(result, "error") do
                  {:error, result["error"]}
                else
                  {:ok, result}
                end

              {:error, reason} ->
                {:error, "Failed to parse detection output: #{inspect(reason)}"}
            end

          {:error, _reason} when exit_code != 0 ->
            # Output file doesn't exist and process failed
            {:error, "Detection failed (exit code #{exit_code})"}

          {:error, reason} ->
            {:error, "Failed to read detection output: #{inspect(reason)}"}
        end
    end
  rescue
    e ->
      Logger.error("leaxer-grounding-dino exception: #{inspect(e)}")
      {:error, "Detection error: #{Exception.message(e)}"}
  end

  @doc """
  Convert detection results to SEGS format for use with other detailer nodes.

  SEGS format:
  %{
    "shape" => [height, width],
    "segments" => [
      %{
        "id" => integer,
        "label" => string,
        "confidence" => float,
        "bbox" => [x1, y1, x2, y2],
        "crop_region" => [x1, y1, x2, y2],  # Expanded for context
        "mask" => nil  # Populated by SAM
      }
    ]
  }
  """
  def to_segs(detection_result, opts \\ []) do
    padding = opts[:padding] || 0

    [width, height] = detection_result["image_size"]

    segments =
      Enum.map(detection_result["detections"], fn det ->
        [x1, y1, x2, y2] = det["bbox"]

        # Calculate crop region with padding
        crop_region = expand_bbox([x1, y1, x2, y2], padding, width, height)

        %{
          "id" => det["id"],
          "label" => det["label"],
          "confidence" => det["confidence"],
          "bbox" => det["bbox"],
          "crop_region" => crop_region,
          "mask" => nil
        }
      end)

    %{
      "shape" => [height, width],
      "segments" => segments
    }
  end

  defp expand_bbox([x1, y1, x2, y2], padding, max_width, max_height) do
    [
      max(0, x1 - padding),
      max(0, y1 - padding),
      min(max_width, x2 + padding),
      min(max_height, y2 + padding)
    ]
  end
end
