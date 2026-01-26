defmodule LeaxerCore.Nodes.Image.SDUpscaler do
  @moduledoc """
  Fast SD Upscaler using native VAE tiling.

  This node provides a streamlined upscaling workflow:
  1. Real-ESRGAN upscales the input image (e.g., 512 → 2048)
  2. ONE sd-server img2img call processes the ENTIRE upscaled image
  3. sd.cpp handles large images internally via VAE tiling (no manual tile loop)

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Why This Is Fast

  This node makes exactly ONE SD call - the server handles memory management
  internally via the `--vae-tiling` flag. No manual tile processing is needed.

  ## Size Limitations

  While VAE tiling handles memory for encode/decode, the UNet still processes
  the full latent space. For very large images, the latent becomes too big:
  - 2048x2048 image = 256x256 latent (OK for most GPUs)
  - 4096x4096 image = 512x512 latent (requires 24GB+ VRAM)

  This node limits the SD refinement to max 2048px on the longest side.
  The final output is then upscaled back to the original ESRGAN size.

  ## Requirements

  The sd-server must be started with `--vae-tiling` enabled (configured in config.exs).
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.{RealESRGAN, Vips}
  alias LeaxerCore.Workers.StableDiffusionServer

  # Max dimension for SD processing (UNet limitation, not VAE)
  # 2048 = 256x256 latent, reasonable for 12GB+ VRAM
  @max_sd_dimension 2048

  @impl true
  def type, do: "SDUpscaler"

  @impl true
  def label, do: "SD Upscaler"

  @impl true
  def category, do: "Image/Upscale"

  @impl true
  def description do
    "Fast AI upscaling: Real-ESRGAN + single SD refinement pass (uses native VAE tiling)"
  end

  @impl true
  def input_spec do
    upscaler_options =
      RealESRGAN.available_models()
      |> Enum.map(fn {key, info} -> %{value: key, label: info.label} end)

    sampler_options = [
      %{value: "euler_a", label: "Euler Ancestral"},
      %{value: "euler", label: "Euler"},
      %{value: "heun", label: "Heun"},
      %{value: "dpm2", label: "DPM2"},
      %{value: "dpm++2s_a", label: "DPM++ 2S Ancestral"},
      %{value: "dpm++2m", label: "DPM++ 2M"},
      %{value: "dpm++2mv2", label: "DPM++ 2M v2"},
      %{value: "lcm", label: "LCM"}
    ]

    %{
      # Required inputs
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image to upscale"
      },
      model: %{
        type: :model,
        label: "MODEL",
        description: "Stable Diffusion model for refinement"
      },

      # Prompts
      positive: %{
        type: :string,
        label: "POSITIVE PROMPT",
        default: "high quality, detailed, sharp focus, 8k",
        multiline: true,
        description: "Prompt for SD refinement"
      },
      negative: %{
        type: :string,
        label: "NEGATIVE PROMPT",
        default: "blurry, artifacts, low quality, noise, jpeg artifacts",
        multiline: true,
        description: "Negative prompt"
      },

      # Upscale settings
      upscaler: %{
        type: :enum,
        label: "UPSCALER",
        default: "realesrgan-x4plus",
        options: upscaler_options,
        description: "Real-ESRGAN model (determines scale factor)"
      },

      # SD settings
      denoise: %{
        type: :float,
        label: "DENOISE STRENGTH",
        default: 0.3,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        description: "How much to refine (0.2-0.4 recommended)"
      },
      steps: %{
        type: :integer,
        label: "STEPS",
        default: 20,
        min: 1,
        max: 50,
        description: "Sampling steps"
      },
      cfg: %{
        type: :float,
        label: "CFG SCALE",
        default: 7.0,
        min: 1.0,
        max: 15.0,
        step: 0.5,
        description: "Classifier-free guidance"
      },
      sampler: %{
        type: :enum,
        label: "SAMPLER",
        default: "euler_a",
        options: sampler_options,
        description: "Sampling method"
      },
      seed: %{
        type: :bigint,
        label: "SEED",
        default: -1,
        description: "-1 for random"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Upscaled and refined image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    model = inputs["model"] || config["model"]

    model_path = extract_path(model)

    with :ok <- validate_image(image),
         :ok <- validate_input(model_path, "Model") do
      # Materialize image to temp file if it's base64
      case Vips.materialize_to_temp(image) do
        {:ok, image_path} ->
          result = do_upscale(image_path, model_path, inputs, config, image)

          # Clean up materialized temp file if input was base64
          unless is_path_based?(image), do: File.rm(image_path)

          result

        {:error, reason} ->
          {:error, "Failed to process image: #{reason}"}
      end
    end
  rescue
    e ->
      Logger.error("[SDUpscaler] Exception: #{inspect(e)}")
      {:error, "SD Upscaler failed: #{Exception.message(e)}"}
  end

  defp do_upscale(image_path, model_path, inputs, config, _original_image) do
    # Get parameters
    upscaler = inputs["upscaler"] || config["upscaler"] || "realesrgan-x4plus"
    positive = inputs["positive"] || config["positive"] || "high quality, detailed"
    negative = inputs["negative"] || config["negative"] || "blurry, low quality"
    denoise = inputs["denoise"] || config["denoise"] || 0.3
    steps = inputs["steps"] || config["steps"] || 20
    cfg = inputs["cfg"] || config["cfg"] || 7.0
    sampler = inputs["sampler"] || config["sampler"] || "euler_a"
    seed = inputs["seed"] || config["seed"] || -1

    scale = RealESRGAN.get_model_scale(upscaler)

    Logger.info(
      "[SDUpscaler] Starting: #{upscaler} (#{scale}x) + SD refinement (denoise=#{denoise})"
    )

    # Step 1: Real-ESRGAN upscale
    temp_dir = LeaxerCore.Paths.tmp_dir()

    upscaled_path =
      Path.join(temp_dir, "sd_upscaler_esrgan_#{:erlang.unique_integer([:positive])}.png")

    case RealESRGAN.upscale(image_path, upscaled_path, model: upscaler) do
      {:ok, esrgan_output} ->
        Logger.info("[SDUpscaler] Real-ESRGAN complete: #{esrgan_output}")

        # Get upscaled dimensions using vips
        case Vips.identify(%{path: esrgan_output}) do
          {:ok, upscaled_info} ->
            original_width = upscaled_info.width
            original_height = upscaled_info.height
            Logger.info("[SDUpscaler] Upscaled size: #{original_width}x#{original_height}")

            # Check if we need to resize for SD (UNet can't handle huge latents)
            {sd_width, sd_height, needs_resize} =
              calculate_sd_dimensions(original_width, original_height)

            # Prepare image for SD (resize if needed)
            sd_input =
              if needs_resize do
                resized_path =
                  Path.join(
                    temp_dir,
                    "sd_upscaler_resized_#{:erlang.unique_integer([:positive])}.png"
                  )

                Logger.info(
                  "[SDUpscaler] Resizing for SD: #{original_width}x#{original_height} → #{sd_width}x#{sd_height}"
                )

                case Vips.resize(%{path: esrgan_output}, sd_width, sd_height,
                       maintain_aspect: false
                     ) do
                  {:ok, resized_result} ->
                    # Write resized to temp file for SD server
                    :ok = Vips.write_to_path(resized_result, resized_path)
                    resized_path

                  {:error, reason} ->
                    Logger.error("[SDUpscaler] Resize failed: #{reason}")
                    esrgan_output
                end
              else
                esrgan_output
              end

            # Step 2: ONE SD img2img call
            # Server has --vae-tiling enabled for VAE memory management
            sd_opts = [
              model: model_path,
              negative_prompt: negative,
              steps: steps,
              cfg_scale: cfg,
              width: sd_width,
              height: sd_height,
              seed: seed,
              sampler: sampler,
              init_img: sd_input,
              strength: denoise,
              node_id: config["node_id"],
              job_id: config["job_id"],
              model_caching_strategy: config["model_caching_strategy"] || "auto"
            ]

            Logger.info(
              "[SDUpscaler] Sending #{sd_width}x#{sd_height} to SD img2img (single call)"
            )

            case StableDiffusionServer.generate(positive, sd_opts) do
              {:ok, %{data: data, mime_type: mime_type}} ->
                # Server returned base64 data
                Logger.info("[SDUpscaler] SD refinement complete (base64)")

                # If we resized, upscale back to original ESRGAN size
                final_result =
                  if needs_resize do
                    Logger.info(
                      "[SDUpscaler] Upscaling result back to #{original_width}x#{original_height}"
                    )

                    case Vips.resize(
                           %{data: data, mime_type: mime_type},
                           original_width,
                           original_height,
                           maintain_aspect: false
                         ) do
                      {:ok, resized_final} -> resized_final
                      {:error, _} -> %{data: data, mime_type: mime_type}
                    end
                  else
                    %{data: data, mime_type: mime_type}
                  end

                Logger.info("[SDUpscaler] Complete")
                {:ok, %{"image" => final_result}}

              {:ok, %{path: result_path}} ->
                # Server returned path (fallback mode)
                Logger.info("[SDUpscaler] SD refinement complete: #{result_path}")

                # Read result as base64
                case File.read(result_path) do
                  {:ok, binary} ->
                    base64_data = Base.encode64(binary)
                    sd_result = %{data: base64_data, mime_type: "image/png"}

                    # If we resized, upscale back to original ESRGAN size
                    final_result =
                      if needs_resize do
                        Logger.info(
                          "[SDUpscaler] Upscaling result back to #{original_width}x#{original_height}"
                        )

                        case Vips.resize(sd_result, original_width, original_height,
                               maintain_aspect: false
                             ) do
                          {:ok, resized_final} -> resized_final
                          {:error, _} -> sd_result
                        end
                      else
                        sd_result
                      end

                    Logger.info("[SDUpscaler] Complete")
                    {:ok, %{"image" => final_result}}

                  {:error, reason} ->
                    {:error, "Failed to read SD result: #{inspect(reason)}"}
                end

              {:error, reason} ->
                {:error, "SD refinement failed: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Failed to get upscaled dimensions: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Real-ESRGAN upscale failed: #{reason}"}
    end
  end

  # Private helpers

  defp extract_path(%{path: path}) when is_binary(path), do: path
  defp extract_path(%{"path" => path}) when is_binary(path), do: path
  defp extract_path(path) when is_binary(path), do: path
  defp extract_path(_), do: nil

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

  defp validate_input(nil, name), do: {:error, "#{name} is required"}

  defp validate_input(path, name) when is_binary(path) do
    if File.exists?(path), do: :ok, else: {:error, "#{name} not found: #{path}"}
  end

  defp validate_input(_, name), do: {:error, "Invalid #{name} input"}

  # Calculate dimensions for SD processing
  # If image is too large, scale down to fit within @max_sd_dimension
  defp calculate_sd_dimensions(width, height) do
    max_dim = max(width, height)

    if max_dim <= @max_sd_dimension do
      # Image fits, round to 64 for SD compatibility
      {round_to_64(width), round_to_64(height), false}
    else
      # Scale down proportionally
      scale = @max_sd_dimension / max_dim
      new_width = round_to_64(round(width * scale))
      new_height = round_to_64(round(height * scale))
      {new_width, new_height, true}
    end
  end

  # SD requires dimensions to be multiples of 64
  defp round_to_64(value) do
    div(value + 63, 64) * 64
  end
end
