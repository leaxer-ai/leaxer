defmodule LeaxerCore.Nodes.Inference.GenerateVideo do
  @moduledoc """
  Generate videos using sd.cpp with Wan2.1/2.2 models.

  This node supports video generation via the -M vid_gen mode in sd.cpp,
  enabling text-to-video (T2V), image-to-video (I2V), and frame-to-frame
  video (FLF2V) generation with Wan models.

  Accepts both base64 and path-based image inputs (init_image, end_image).

  ## Modes
  - T2V (text-to-video): Just provide prompt, no init/end images
  - I2V (image-to-video): Provide init_image to animate from that image
  - FLF2V (first-last-frame): Provide both init_image and end_image for frame interpolation
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Vips

  @impl true
  def type, do: "GenerateVideo"

  @impl true
  def label, do: "Generate Video"

  @impl true
  def category, do: "Inference/Generate"

  @impl true
  def description,
    do: "Generate a video using Wan2.1/2.2 models (supports T2V, I2V, and FLF2V modes)"

  @impl true
  def input_spec do
    %{
      model: %{type: :model, label: "MODEL"},
      prompt: %{type: :string, label: "PROMPT", default: "", multiline: true},
      negative_prompt: %{type: :string, label: "NEGATIVE PROMPT", default: "", multiline: true},
      # I2V/FLF2V inputs
      init_image: %{
        type: :image,
        label: "INIT IMAGE",
        optional: true,
        description: "Initial frame for I2V mode"
      },
      end_image: %{
        type: :image,
        label: "END IMAGE",
        optional: true,
        description: "End frame for FLF2V mode (requires init_image)"
      },
      clip_vision: %{
        type: :string,
        label: "CLIP VISION",
        default: "",
        optional: true,
        description: "Path to CLIP vision model for I2V/FLF2V"
      },
      video_frames: %{
        type: :integer,
        label: "VIDEO FRAMES",
        default: 17,
        min: 1,
        max: 33,
        step: 1
      },
      fps: %{type: :integer, label: "FPS", default: 24, min: 1, max: 60, step: 1},
      flow_shift: %{
        type: :float,
        label: "FLOW SHIFT",
        default: 7.0,
        min: 0.0,
        max: 20.0,
        step: 0.5
      },
      vace_strength: %{
        type: :float,
        label: "VACE STRENGTH",
        default: 1.0,
        min: 0.0,
        max: 2.0,
        step: 0.1,
        optional: true
      },
      width: %{type: :integer, label: "WIDTH", default: 512, min: 64, max: 2048, step: 64},
      height: %{type: :integer, label: "HEIGHT", default: 512, min: 64, max: 2048, step: 64},
      steps: %{type: :integer, label: "STEPS", default: 20, min: 1, max: 150, step: 1},
      cfg_scale: %{type: :float, label: "CFG SCALE", default: 7.0, min: 1.0, max: 30.0, step: 0.5},
      seed: %{type: :bigint, label: "SEED", default: -1}
    }
  end

  @impl true
  def output_spec do
    %{
      video: %{type: :video, label: "VIDEO"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "GenerateVideoNode"}

  @impl true
  def process(inputs, config) do
    # Get model path from connected input or config
    model_path =
      case inputs["model"] do
        %{path: path} -> path
        path when is_binary(path) -> path
        _ -> config["model"]
      end

    if is_nil(model_path) or model_path == "" do
      {:error, "No model selected"}
    else
      prompt = inputs["prompt"] || config["prompt"] || ""

      if prompt == "" do
        {:error, "Prompt is required"}
      else
        # Build video-specific options
        video_frames = inputs["video_frames"] || config["video_frames"] || 17
        fps = inputs["fps"] || config["fps"] || 24
        flow_shift = inputs["flow_shift"] || config["flow_shift"] || 7.0
        vace_strength = inputs["vace_strength"] || config["vace_strength"]

        # Clamp video_frames to valid range
        video_frames = max(1, min(33, video_frames))

        # Get model caching strategy from system settings
        strategy = config["model_caching_strategy"] || "auto"

        # Build I2V options (returns {opts, temp_files})
        {i2v_opts, temp_files} = build_i2v_opts(inputs, config)

        opts =
          [
            model: model_path,
            negative_prompt: inputs["negative_prompt"] || config["negative_prompt"] || "",
            steps: inputs["steps"] || config["steps"] || 20,
            cfg_scale: inputs["cfg_scale"] || config["cfg_scale"] || 7.0,
            width: inputs["width"] || config["width"] || 512,
            height: inputs["height"] || config["height"] || 512,
            seed: inputs["seed"] || config["seed"] || -1,
            compute_backend: config["compute_backend"] || "cpu",
            node_id: config["node_id"],
            job_id: config["job_id"],
            # Video-specific options
            mode: "vid_gen",
            video_frames: video_frames,
            fps: fps,
            flow_shift: flow_shift
          ] ++
            build_vace_opts(vace_strength) ++
            i2v_opts

        # Select worker based on system caching strategy
        worker =
          case strategy do
            "server-mode" ->
              LeaxerCore.Workers.StableDiffusionServer

            "cli-mode" ->
              LeaxerCore.Workers.StableDiffusion

            _ ->
              if LeaxerCore.Workers.StableDiffusionServer.available?() do
                LeaxerCore.Workers.StableDiffusionServer
              else
                LeaxerCore.Workers.StableDiffusion
              end
          end

        result =
          case worker.generate(prompt, opts) do
            {:ok, result} ->
              {:ok, %{"video" => %{path: result.path, type: :video}}}

            {:error, reason} ->
              {:error, reason}
          end

        # Cleanup temp files
        cleanup_temp_files(temp_files)

        result
      end
    end
  end

  # Private helper functions

  defp build_vace_opts(nil), do: []

  defp build_vace_opts(vace_strength) when is_number(vace_strength) do
    # Clamp to valid range
    clamped = max(0.0, min(2.0, vace_strength))
    [vace_strength: clamped]
  end

  defp build_vace_opts(_), do: []

  # Build I2V/FLF2V options for image-to-video and frame-to-frame generation
  # Returns {opts, temp_files} to track files needing cleanup
  defp build_i2v_opts(inputs, config) do
    init_image = inputs["init_image"]
    end_image = inputs["end_image"]
    clip_vision = inputs["clip_vision"] || config["clip_vision"]

    opts = []
    temp_files = []

    # Add init image for I2V mode (materialize if base64)
    {opts, temp_files} =
      case materialize_image(init_image) do
        {:ok, path, temp_file} ->
          temps = if temp_file, do: [temp_file | temp_files], else: temp_files
          {opts ++ [init_img: path], temps}

        _ ->
          {opts, temp_files}
      end

    # Add end image for FLF2V mode (only valid if init_image is also set)
    {opts, temp_files} =
      if Keyword.has_key?(opts, :init_img) do
        case materialize_image(end_image) do
          {:ok, path, temp_file} ->
            temps = if temp_file, do: [temp_file | temp_files], else: temp_files
            {opts ++ [end_img: path], temps}

          _ ->
            {opts, temp_files}
        end
      else
        {opts, temp_files}
      end

    # Add CLIP vision model if provided (needed for I2V/FLF2V)
    opts =
      case clip_vision do
        nil -> opts
        "" -> opts
        path when is_binary(path) -> opts ++ [clip_vision: path]
        _ -> opts
      end

    {opts, temp_files}
  end

  # Materialize image to temp file if base64, return {:ok, path, temp_file_or_nil}
  defp materialize_image(%{data: _, mime_type: _} = image) do
    case Vips.materialize_to_temp(image) do
      {:ok, path} -> {:ok, path, path}
      {:error, _} -> :error
    end
  end

  defp materialize_image(%{"data" => _, "mime_type" => _} = image) do
    case Vips.materialize_to_temp(image) do
      {:ok, path} -> {:ok, path, path}
      {:error, _} -> :error
    end
  end

  defp materialize_image(%{path: path}) when is_binary(path), do: {:ok, path, nil}
  defp materialize_image(%{"path" => path}) when is_binary(path), do: {:ok, path, nil}
  defp materialize_image(path) when is_binary(path), do: {:ok, path, nil}
  defp materialize_image(_), do: :error

  defp cleanup_temp_files(files) do
    Enum.each(files, fn file ->
      if file && File.exists?(file), do: File.rm(file)
    end)
  end
end
