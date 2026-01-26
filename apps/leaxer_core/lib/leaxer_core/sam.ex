defmodule LeaxerCore.SAM do
  @moduledoc """
  Wrapper for leaxer-sam command-line operations.
  Provides interface for Segment Anything Model (SAM) segmentation using ONNX Runtime.
  """

  alias LeaxerCore.BinaryFinder

  require Logger

  @doc """
  Get the path to the leaxer-sam binary.
  """
  def bin_path do
    BinaryFinder.priv_bin_path("leaxer-sam")
  end

  @doc """
  Get the path to the SAM models directory.
  """
  def models_path do
    Path.join([LeaxerCore.Paths.models_dir(), "sam"])
  end

  @doc """
  Check if leaxer-sam is installed and available.
  Returns {:ok, binary_path} if available, {:error, reason} otherwise.
  """
  def check_installation do
    path = bin_path()

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "leaxer-sam binary not found at #{path}"}
    end
  end

  @doc """
  Check if a model is downloaded and available.
  SAM ONNX models have two files: encoder and decoder.
  """
  def check_model(model_name \\ "mobile_sam") do
    {encoder_file, decoder_file} = model_filenames(model_name)
    encoder_path = Path.join(models_path(), encoder_file)
    decoder_path = Path.join(models_path(), decoder_file)

    cond do
      not File.exists?(encoder_path) ->
        {:error, "Encoder not found at #{encoder_path}. Please download the model first."}

      not File.exists?(decoder_path) ->
        {:error, "Decoder not found at #{decoder_path}. Please download the model first."}

      true ->
        {:ok, encoder_path}
    end
  end

  defp model_filenames(model_name) do
    # ONNX models have separate encoder and decoder files
    {"#{model_name}_encoder.onnx", "#{model_name}_decoder.onnx"}
  end

  @doc """
  Get available models with their descriptions.
  ONNX models have separate encoder and decoder files.
  """
  def available_models do
    base_url = "https://github.com/leaxer-ai/leaxer-sam/releases/download/v0.1.0"

    %{
      "mobile_sam" => %{
        label: "MobileSAM",
        size: "55MB",
        speed: "fast",
        quality: "good",
        description: "Fast, lightweight segmentation (ONNX)",
        download_urls: [
          "#{base_url}/mobile_sam_encoder.onnx",
          "#{base_url}/mobile_sam_decoder.onnx"
        ]
      },
      "sam_vit_b" => %{
        label: "SAM ViT-B",
        size: "365MB",
        speed: "medium",
        quality: "better",
        description: "Good balance of speed and quality (ONNX)",
        download_urls: [
          "#{base_url}/sam_vit_b_encoder.onnx",
          "#{base_url}/sam_vit_b_decoder.onnx"
        ]
      }
    }
  end

  @doc """
  Segment objects using bounding box prompts.

  ## Options
  - `:model` - Model name (default: "mobile_sam")

  ## Examples

      iex> segment_boxes("input.jpg", [[100, 50, 200, 180], [300, 200, 380, 320]])
      {:ok, %{
        "segments" => [
          %{"id" => 0, "bbox" => [100, 50, 200, 180], "confidence" => 0.98, "mask_path" => "/tmp/masks/mask_0.png"}
        ]
      }}
  """
  def segment_boxes(image_path, boxes, opts \\ []) do
    with {:ok, _} <- check_installation(),
         :ok <- validate_input(image_path) do
      do_segment_boxes(image_path, boxes, opts)
    end
  end

  @doc """
  Segment objects using point prompts.

  ## Options
  - `:model` - Model name (default: "mobile_sam")
  - `:labels` - Point labels (1=foreground, 0=background)
  """
  def segment_points(image_path, points, opts \\ []) do
    with {:ok, _} <- check_installation(),
         :ok <- validate_input(image_path) do
      do_segment_points(image_path, points, opts)
    end
  end

  @doc """
  Automatically segment all objects in an image.

  ## Options
  - `:model` - Model name (default: "mobile_sam")
  - `:points_per_side` - Grid density (default: 32)
  - `:min_area` - Minimum mask area (default: 100)
  """
  def segment_everything(image_path, opts \\ []) do
    with {:ok, _} <- check_installation(),
         :ok <- validate_input(image_path) do
      do_segment_everything(image_path, opts)
    end
  end

  @doc """
  Process SEGS with SAM to add precise masks.
  Takes SEGS from GroundingDINO and adds pixel-level masks.
  """
  def process_segs(image_path, segs, opts \\ []) do
    boxes = Enum.map(segs["segments"], & &1["bbox"])

    case segment_boxes(image_path, boxes, opts) do
      {:ok, result} ->
        # Merge SAM results back into SEGS
        updated_segments =
          segs["segments"]
          |> Enum.zip(result["segments"])
          |> Enum.map(fn {seg, sam_result} ->
            Map.merge(seg, %{
              "mask_path" => sam_result["mask_path"],
              "mask_confidence" => sam_result["confidence"]
            })
          end)

        {:ok, Map.put(segs, "segments", updated_segments)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_input(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "Input file not found: #{path}"}
    end
  end

  defp do_segment_boxes(image_path, boxes, opts) do
    model = opts[:model] || "mobile_sam"

    # Create temp directory for masks
    output_dir =
      Path.join(System.tmp_dir!(), "sam_masks_#{:erlang.unique_integer([:positive])}")

    json_path = "#{output_dir}.json"

    args = [
      "segment",
      "--image",
      image_path,
      "--boxes",
      Jason.encode!(boxes),
      "--model",
      model,
      "--output",
      output_dir,
      "--json",
      json_path
    ]

    Logger.info("Running leaxer-sam: #{bin_path()} #{Enum.join(args, " ")}")

    case System.cmd(bin_path(), args, stderr_to_stdout: true) do
      {_output, 0} ->
        parse_sam_output(json_path)

      {error, code} ->
        Logger.error("leaxer-sam failed (exit #{code}): #{error}")
        {:error, "Segmentation failed: #{error}"}
    end
  rescue
    e ->
      Logger.error("leaxer-sam exception: #{inspect(e)}")
      {:error, "Segmentation error: #{Exception.message(e)}"}
  end

  defp do_segment_points(image_path, points, opts) do
    model = opts[:model] || "mobile_sam"
    labels = opts[:labels] || List.duplicate(1, length(points))

    output_dir =
      Path.join(System.tmp_dir!(), "sam_masks_#{:erlang.unique_integer([:positive])}")

    json_path = "#{output_dir}.json"

    args = [
      "segment",
      "--image",
      image_path,
      "--points",
      Jason.encode!(points),
      "--labels",
      Jason.encode!(labels),
      "--model",
      model,
      "--output",
      output_dir,
      "--json",
      json_path
    ]

    Logger.info("Running leaxer-sam: #{bin_path()} #{Enum.join(args, " ")}")

    case System.cmd(bin_path(), args, stderr_to_stdout: true) do
      {_output, 0} ->
        parse_sam_output(json_path)

      {error, code} ->
        Logger.error("leaxer-sam failed (exit #{code}): #{error}")
        {:error, "Segmentation failed: #{error}"}
    end
  rescue
    e ->
      Logger.error("leaxer-sam exception: #{inspect(e)}")
      {:error, "Segmentation error: #{Exception.message(e)}"}
  end

  defp do_segment_everything(image_path, opts) do
    model = opts[:model] || "mobile_sam"
    points_per_side = opts[:points_per_side] || 32
    min_area = opts[:min_area] || 100

    output_dir =
      Path.join(System.tmp_dir!(), "sam_masks_#{:erlang.unique_integer([:positive])}")

    json_path = "#{output_dir}.json"

    args = [
      "auto",
      "--image",
      image_path,
      "--model",
      model,
      "--points-per-side",
      to_string(points_per_side),
      "--min-area",
      to_string(min_area),
      "--output",
      output_dir,
      "--json",
      json_path
    ]

    Logger.info("Running leaxer-sam: #{bin_path()} #{Enum.join(args, " ")}")

    case System.cmd(bin_path(), args, stderr_to_stdout: true) do
      {_output, 0} ->
        parse_sam_output(json_path)

      {error, code} ->
        Logger.error("leaxer-sam failed (exit #{code}): #{error}")
        {:error, "Segmentation failed: #{error}"}
    end
  rescue
    e ->
      Logger.error("leaxer-sam exception: #{inspect(e)}")
      {:error, "Segmentation error: #{Exception.message(e)}"}
  end

  defp parse_sam_output(json_path) do
    case File.read(json_path) do
      {:ok, json} ->
        File.rm(json_path)

        case Jason.decode(json) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            {:error, "Failed to parse segmentation output: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read segmentation output: #{inspect(reason)}"}
    end
  end
end
