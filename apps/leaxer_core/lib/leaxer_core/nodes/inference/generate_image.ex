defmodule LeaxerCore.Nodes.Inference.GenerateImage do
  @moduledoc """
  Generate images using stable-diffusion.cpp.

  This node takes a model and prompt, runs inference via the sd.cpp worker,
  and outputs the generated image path.

  Accepts both base64 and path-based image inputs (init_image, control_image, mask_image, ref_images).
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Vips

  @impl true
  def type, do: "GenerateImage"

  @impl true
  def label, do: "Generate Image"

  @impl true
  def category, do: "Inference/Generate"

  @impl true
  def description, do: "Generate an image using Stable Diffusion"

  @impl true
  def input_spec do
    %{
      model: %{type: :model, label: "MODEL"},
      prompt: %{type: :string, label: "POSITIVE PROMPT", default: "", multiline: true},
      negative_prompt: %{type: :string, label: "NEGATIVE PROMPT", default: "", multiline: true},
      steps: %{type: :integer, label: "STEPS", default: 20, min: 1, max: 150, step: 1},
      cfg_scale: %{type: :float, label: "CFG SCALE", default: 7.0, min: 1.0, max: 30.0, step: 0.5},
      width: %{type: :integer, label: "WIDTH", default: 512, min: 64, max: 2048, step: 64},
      height: %{type: :integer, label: "HEIGHT", default: 512, min: 64, max: 2048, step: 64},
      seed: %{type: :bigint, label: "SEED", default: -1},
      init_image: %{type: :image, label: "INIT IMAGE", optional: true},
      strength: %{
        type: :float,
        label: "STRENGTH",
        default: 0.75,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        optional: true
      },
      lora: %{type: :lora, label: "LORA", optional: true},
      lora_stack: %{type: :lora_stack, label: "STACKED LORAS", optional: true},
      control_net: %{type: :controlnet, label: "CONTROLNET", optional: true},
      control_image: %{type: :image, label: "CONTROL IMAGE", optional: true},
      mask_image: %{type: :image, label: "MASK IMAGE", optional: true},
      vae: %{type: :vae, label: "VAE", optional: true},
      photo_maker: %{type: :photo_maker, label: "PHOTOMAKER", optional: true},
      text_encoders: %{type: :text_encoders, label: "TEXT ENCODERS", optional: true},
      chroma_settings: %{type: :chroma_settings, label: "CHROMA SETTINGS", optional: true},
      cache_settings: %{type: :cache_settings, label: "CACHE SETTINGS", optional: true},
      sampler_settings: %{type: :sampler_settings, label: "SAMPLER SETTINGS", optional: true},
      ref_images: %{type: :image_array, label: "REFERENCE IMAGES", optional: true},
      preview_method: %{
        type: :enum,
        label: "PREVIEW METHOD",
        default: "none",
        optional: true,
        options: [
          %{value: "none", label: "None"},
          %{value: "proj", label: "Projection (fast, low quality)"},
          %{value: "tae", label: "TAESD (fast, good quality)"},
          %{value: "vae", label: "VAE (slow, best quality)"}
        ],
        description: "Preview method for intermediate steps"
      },
      taesd_path: %{
        type: :string,
        label: "TAESD PATH",
        default: "",
        optional: true,
        description: "Path to TAESD model for TAE preview"
      },
      preview_interval: %{
        type: :integer,
        label: "PREVIEW INTERVAL",
        default: 5,
        min: 1,
        max: 50,
        step: 1,
        optional: true,
        description: "Steps between preview updates"
      },
      sampler: %{
        type: :enum,
        label: "SAMPLER",
        default: "euler_a",
        options: [
          %{value: "euler", label: "Euler"},
          %{value: "euler_a", label: "Euler Ancestral"},
          %{value: "heun", label: "Heun"},
          %{value: "dpm2", label: "DPM2"},
          %{value: "dpm++2s_a", label: "DPM++ 2S Ancestral"},
          %{value: "dpm++2m", label: "DPM++ 2M"},
          %{value: "dpm++2mv2", label: "DPM++ 2M v2"},
          %{value: "lcm", label: "LCM"}
        ]
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{type: :image, label: "IMAGE"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "GenerateImageNode"}

  @impl true
  def process(inputs, config) do
    # Get model path and weight_type from connected input or config
    {model_path, weight_type} =
      case inputs["model"] do
        %{path: path, weight_type: wt} -> {path, wt}
        %{path: path} -> {path, "default"}
        path when is_binary(path) -> {path, "default"}
        _ -> {config["model"], "default"}
      end

    if is_nil(model_path) or model_path == "" do
      {:error, "No model selected"}
    else
      base_prompt = inputs["prompt"] || config["prompt"] || ""

      if base_prompt == "" do
        {:error, "Prompt is required"}
      else
        # Process LoRA(s) and inject into prompt if provided
        lora_input = inputs["lora_stack"] || inputs["lora"]
        {prompt, lora_opts} = process_lora_input(base_prompt, lora_input)

        # Process ControlNet if provided (returns {opts, temp_files})
        {controlnet_opts, controlnet_temps} =
          process_controlnet_input(inputs["control_net"], inputs["control_image"])

        # Process img2img if provided (returns {opts, temp_files})
        {img2img_opts, img2img_temps} =
          process_img2img_input(inputs["init_image"], inputs["strength"])

        # Process inpainting if provided (returns {opts, temp_files})
        {inpainting_opts, inpainting_temps} = process_inpainting_input(inputs["mask_image"])

        # Process VAE if provided
        vae_opts = process_vae_input(inputs["vae"])

        # Process PhotoMaker if provided
        photo_maker_opts = process_photo_maker_input(inputs["photo_maker"])

        # Process text encoders if provided (FLUX.1, SD3.5)
        text_encoder_opts = process_text_encoder_input(inputs["text_encoders"])

        # Process Chroma settings if provided
        chroma_opts = process_chroma_input(inputs["chroma_settings"])

        # Process cache settings if provided
        cache_opts = process_cache_input(inputs["cache_settings"])

        # Process sampler settings if provided
        sampler_opts = process_sampler_input(inputs["sampler_settings"])

        # Process reference images if provided (returns {opts, temp_files})
        {ref_images_opts, ref_images_temps} = process_ref_images_input(inputs["ref_images"])

        # Collect all temp files for cleanup
        temp_files = controlnet_temps ++ img2img_temps ++ inpainting_temps ++ ref_images_temps

        # Process preview/TAESD settings if provided
        preview_opts = process_preview_input(inputs, config)

        # Detect model type and get appropriate defaults
        {default_cfg, default_sampler} = detect_model_defaults(model_path)

        # Get model caching strategy from system settings (passed via config)
        strategy = config["model_caching_strategy"] || "auto"

        # Use detected defaults unless user explicitly overrides
        cfg_scale = inputs["cfg_scale"] || config["cfg_scale"] || default_cfg

        # Sampler from settings node takes priority over basic sampler input
        sampler =
          case inputs["sampler_settings"] do
            %{method: method} -> method
            _ -> inputs["sampler"] || config["sampler"] || default_sampler
          end

        # Process weight_type option (for GGUF models)
        weight_type_opts = process_weight_type(weight_type)

        opts =
          [
            model: model_path,
            negative_prompt: inputs["negative_prompt"] || config["negative_prompt"] || "",
            steps: inputs["steps"] || config["steps"] || 20,
            cfg_scale: cfg_scale,
            width: inputs["width"] || config["width"] || 512,
            height: inputs["height"] || config["height"] || 512,
            seed: inputs["seed"] || config["seed"] || -1,
            sampler: sampler,
            compute_backend: config["compute_backend"] || "cpu",
            node_id: config["node_id"],
            job_id: config["job_id"],
            # Return base64 data to keep images in memory (no disk write)
            stream_base64: true
          ] ++
            weight_type_opts ++
            lora_opts ++
            controlnet_opts ++
            img2img_opts ++
            inpainting_opts ++
            vae_opts ++
            photo_maker_opts ++
            text_encoder_opts ++
            chroma_opts ++ cache_opts ++ sampler_opts ++ ref_images_opts ++ preview_opts

        # Select worker based on system caching strategy
        worker =
          case strategy do
            "server-mode" ->
              # Always use server mode
              LeaxerCore.Workers.StableDiffusionServer

            "cli-mode" ->
              # Always use CLI mode
              LeaxerCore.Workers.StableDiffusion

            _ ->
              # Auto mode: use server if available, otherwise CLI
              if LeaxerCore.Workers.StableDiffusionServer.available?() do
                LeaxerCore.Workers.StableDiffusionServer
              else
                LeaxerCore.Workers.StableDiffusion
              end
          end

        result =
          case worker.generate(prompt, opts) do
            {:ok, %{data: data, mime_type: mime_type}} ->
              # Server mode returns base64 data - keep in memory
              {:ok, %{"image" => %{data: data, mime_type: mime_type, type: :image}}}

            {:ok, %{path: path}} ->
              # CLI mode returns file path - read as base64
              case File.read(path) do
                {:ok, binary} ->
                  base64_data = Base.encode64(binary)
                  {:ok, %{"image" => %{data: base64_data, mime_type: "image/png", type: :image}}}

                {:error, _} ->
                  # Fallback to path if read fails
                  {:ok, %{"image" => %{path: path, type: :image}}}
              end

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

  # Weight type processing (for GGUF quantization)
  defp process_weight_type("default"), do: []
  defp process_weight_type(nil), do: []
  defp process_weight_type(weight_type), do: [weight_type: weight_type]

  defp process_lora_input(prompt, nil), do: {prompt, []}

  # Handle stacked LoRAs
  defp process_lora_input(prompt, %{type: :lora_stack, loras: loras}) when is_list(loras) do
    # Process each LoRA and collect tags and options
    {lora_tags, all_opts} =
      loras
      |> Enum.reduce({[], []}, fn lora, {tags_acc, opts_acc} ->
        case {lora.path, lora.multiplier, lora.apply_mode} do
          {path, multiplier, apply_mode} when is_binary(path) ->
            # Extract model name from path for prompt injection
            model_name = path |> Path.basename() |> Path.rootname()
            lora_tag = "<lora:#{model_name}:#{multiplier}>"

            # Collect directory and apply mode (use the first one as base)
            opts =
              if length(opts_acc) == 0 do
                [
                  lora_model_dir: Path.dirname(path),
                  lora_apply_mode: apply_mode
                ]
              else
                opts_acc
              end

            {[lora_tag | tags_acc], opts}

          _ ->
            {tags_acc, opts_acc}
        end
      end)

    # Inject all LoRA tags into prompt
    enhanced_prompt = "#{prompt} #{Enum.join(Enum.reverse(lora_tags), " ")}"
    {enhanced_prompt, all_opts}
  end

  # Handle single LoRA
  defp process_lora_input(prompt, lora) when is_map(lora) do
    case {lora.path, lora.multiplier, lora.apply_mode} do
      {path, multiplier, apply_mode} when is_binary(path) ->
        # Extract model name from path for prompt injection
        model_name = path |> Path.basename() |> Path.rootname()

        # Inject LoRA tag into prompt: <lora:name:multiplier>
        lora_tag = "<lora:#{model_name}:#{multiplier}>"
        enhanced_prompt = "#{prompt} #{lora_tag}"

        # Prepare worker options
        lora_opts = [
          lora_model_dir: Path.dirname(path),
          lora_apply_mode: apply_mode
        ]

        {enhanced_prompt, lora_opts}

      _ ->
        {prompt, []}
    end
  end

  defp process_lora_input(prompt, _), do: {prompt, []}

  # ControlNet processing helper functions

  defp process_controlnet_input(nil, _), do: {[], []}
  defp process_controlnet_input(_, nil), do: {[], []}

  defp process_controlnet_input(controlnet, control_image)
       when is_map(controlnet) and is_map(control_image) do
    controlnet_path = controlnet[:path] || controlnet["path"]
    strength = controlnet[:strength] || controlnet["strength"]
    keep_on_cpu = controlnet[:keep_on_cpu] || controlnet["keep_on_cpu"]

    case materialize_image(control_image) do
      {:ok, image_path, temp_file} when is_binary(controlnet_path) ->
        opts = [
          control_net: controlnet_path,
          control_image: image_path,
          control_strength: strength
        ]

        opts = if keep_on_cpu, do: opts ++ [control_net_cpu: true], else: opts
        temp_files = if temp_file, do: [temp_file], else: []
        {opts, temp_files}

      _ ->
        {[], []}
    end
  end

  defp process_controlnet_input(_, _), do: {[], []}

  # img2img processing helper functions

  defp process_img2img_input(nil, _), do: {[], []}

  defp process_img2img_input(init_image, strength) when is_map(init_image) do
    case materialize_image(init_image) do
      {:ok, path, temp_file} ->
        opts = [init_img: path]

        # Add strength if provided, otherwise use default (0.75)
        strength_value = if strength != nil, do: strength, else: 0.75
        clamped_strength = max(0.0, min(1.0, strength_value))

        opts = opts ++ [strength: clamped_strength]
        temp_files = if temp_file, do: [temp_file], else: []
        {opts, temp_files}

      _ ->
        {[], []}
    end
  end

  defp process_img2img_input(_, _), do: {[], []}

  # Inpainting processing helper functions

  defp process_inpainting_input(nil), do: {[], []}

  defp process_inpainting_input(mask_image) when is_map(mask_image) do
    case materialize_image(mask_image) do
      {:ok, path, temp_file} ->
        temp_files = if temp_file, do: [temp_file], else: []
        {[mask: path], temp_files}

      _ ->
        {[], []}
    end
  end

  defp process_inpainting_input(_), do: {[], []}

  # VAE processing helper functions

  defp process_vae_input(nil), do: []

  defp process_vae_input(vae) when is_map(vae) do
    case vae.path do
      path when is_binary(path) ->
        opts = [vae: path]

        # Add VAE tiling if enabled
        opts =
          if vae.tiling do
            opts ++ [vae_tiling: true, vae_tile_size: vae.tile_size]
          else
            opts
          end

        # Add CPU offload if enabled
        opts =
          if vae.on_cpu do
            opts ++ [vae_on_cpu: true]
          else
            opts
          end

        opts

      _ ->
        []
    end
  end

  defp process_vae_input(_), do: []

  # PhotoMaker processing helper functions

  defp process_photo_maker_input(nil), do: []

  defp process_photo_maker_input(photo_maker) when is_map(photo_maker) do
    case photo_maker.model_path do
      path when is_binary(path) and path != "" ->
        opts = [
          photo_maker: path,
          pm_id_images_dir: photo_maker.id_images_dir,
          pm_style_strength: photo_maker.style_strength
        ]

        # Add ID embedding path if provided (for PhotoMaker v2)
        if photo_maker.id_embed_path do
          opts ++ [pm_id_embed_path: photo_maker.id_embed_path]
        else
          opts
        end

      _ ->
        []
    end
  end

  defp process_photo_maker_input(_), do: []

  # Text encoder processing helper functions (FLUX.1, SD3.5)

  defp process_text_encoder_input(nil), do: []

  defp process_text_encoder_input(text_encoders) when is_map(text_encoders) do
    opts = []

    # Add CLIP L encoder if provided
    opts =
      case text_encoders[:clip_l] do
        nil -> opts
        "" -> opts
        path when is_binary(path) -> opts ++ [clip_l: path]
        _ -> opts
      end

    # Add CLIP G encoder if provided (for SD3.5)
    opts =
      case text_encoders[:clip_g] do
        nil -> opts
        "" -> opts
        path when is_binary(path) -> opts ++ [clip_g: path]
        _ -> opts
      end

    # Add T5-XXL encoder if provided
    opts =
      case text_encoders[:t5xxl] do
        nil -> opts
        "" -> opts
        path when is_binary(path) -> opts ++ [t5xxl: path]
        _ -> opts
      end

    # Add clip_on_cpu flag if enabled
    if text_encoders[:clip_on_cpu] do
      opts ++ [clip_on_cpu: true]
    else
      opts
    end
  end

  defp process_text_encoder_input(_), do: []

  # Chroma settings processing helper functions

  defp process_chroma_input(nil), do: []

  defp process_chroma_input(chroma_settings) when is_map(chroma_settings) do
    opts = []

    # Add disable DiT mask if enabled
    opts =
      if chroma_settings[:disable_dit_mask] do
        opts ++ [chroma_disable_dit_mask: true]
      else
        opts
      end

    # Add enable T5 mask if enabled
    opts =
      if chroma_settings[:enable_t5_mask] do
        opts ++ [chroma_enable_t5_mask: true]
      else
        opts
      end

    # Add T5 mask pad if non-zero
    case chroma_settings[:t5_mask_pad] do
      nil -> opts
      0 -> opts
      pad -> opts ++ [chroma_t5_mask_pad: pad]
    end
  end

  defp process_chroma_input(_), do: []

  # Cache settings processing helper functions

  defp process_cache_input(nil), do: []

  defp process_cache_input(cache_settings) when is_map(cache_settings) do
    mode = cache_settings[:mode] || "none"

    case mode do
      "none" ->
        []

      cache_mode ->
        opts = [cache_mode: cache_mode]

        # Add preset
        opts =
          case cache_settings[:preset] do
            nil -> opts
            "medium" -> opts
            preset -> opts ++ [cache_preset: preset]
          end

        # Add threshold if not default
        opts =
          case cache_settings[:threshold] do
            nil -> opts
            0.5 -> opts
            threshold -> opts ++ [cache_threshold: threshold]
          end

        # Add warmup if not default
        opts =
          case cache_settings[:warmup] do
            nil -> opts
            2 -> opts
            warmup -> opts ++ [cache_warmup: warmup]
          end

        # Add start_step if not default
        opts =
          case cache_settings[:start_step] do
            nil -> opts
            0 -> opts
            start_step -> opts ++ [cache_start_step: start_step]
          end

        # Add end_step if not default (-1 means until end)
        case cache_settings[:end_step] do
          nil -> opts
          -1 -> opts
          end_step -> opts ++ [cache_end_step: end_step]
        end
    end
  end

  defp process_cache_input(_), do: []

  # Sampler settings processing helper functions

  defp process_sampler_input(nil), do: []

  defp process_sampler_input(sampler_settings) when is_map(sampler_settings) do
    opts = []

    # Add scheduler if not default
    opts =
      case sampler_settings[:scheduler] do
        nil -> opts
        "discrete" -> opts
        scheduler -> opts ++ [scheduler: scheduler]
      end

    # Add eta if not default (0.0)
    case sampler_settings[:eta] do
      nil -> opts
      eta when eta == 0.0 -> opts
      eta -> opts ++ [eta: eta]
    end
  end

  defp process_sampler_input(_), do: []

  # Reference images processing helper functions

  defp process_ref_images_input(nil), do: {[], []}
  defp process_ref_images_input([]), do: {[], []}

  defp process_ref_images_input(ref_images) when is_list(ref_images) do
    # Materialize each image and collect paths and temp files
    {paths, temp_files} =
      ref_images
      |> Enum.filter(&is_map/1)
      |> Enum.reduce({[], []}, fn image, {paths_acc, temps_acc} ->
        case materialize_image(image) do
          {:ok, path, temp_file} ->
            temps = if temp_file, do: [temp_file | temps_acc], else: temps_acc
            {[path | paths_acc], temps}

          _ ->
            {paths_acc, temps_acc}
        end
      end)

    paths = Enum.reverse(paths)

    opts =
      case paths do
        [] ->
          []

        [single_path] ->
          [ref_image: single_path]

        [first_path | rest_paths] ->
          base_opts = [ref_image: first_path]
          additional_opts = Enum.map(rest_paths, fn path -> {:additional_ref_image, path} end)
          base_opts ++ additional_opts ++ [increase_ref_index: true]
      end

    {opts, temp_files}
  end

  defp process_ref_images_input(_), do: {[], []}

  # Preview/TAESD settings processing helper functions

  defp process_preview_input(inputs, config) do
    preview_method = inputs["preview_method"] || config["preview_method"] || "none"

    case preview_method do
      "none" ->
        []

      method ->
        opts = [preview: method]

        # Add TAESD path if using TAE method
        opts =
          if method == "tae" do
            taesd_path = inputs["taesd_path"] || config["taesd_path"]

            if taesd_path && taesd_path != "" do
              opts ++ [taesd: taesd_path]
            else
              opts
            end
          else
            opts
          end

        # Add preview interval
        case inputs["preview_interval"] || config["preview_interval"] do
          nil -> opts
          interval -> opts ++ [preview_interval: interval]
        end
    end
  end

  # Model detection for auto-setting appropriate defaults

  defp detect_model_defaults(model_path) when is_binary(model_path) do
    # Normalize path for pattern matching
    model_lower = String.downcase(model_path)

    cond do
      # FLUX.2 models: cfg_scale 1.0, euler sampler (klein variants)
      String.contains?(model_lower, "flux") and
          (String.contains?(model_lower, "klein") or String.contains?(model_lower, "flux.2") or
             String.contains?(model_lower, "flux2")) ->
        {1.0, "euler"}

      # FLUX.1 models: cfg_scale 1.0, euler sampler
      String.contains?(model_lower, "flux") and
          (String.contains?(model_lower, "dev") or String.contains?(model_lower, "schnell") or
             String.contains?(model_lower, "kontext")) ->
        {1.0, "euler"}

      # SD3.5 models: default cfg 5.0, euler sampler
      String.contains?(model_lower, "sd3") or String.contains?(model_lower, "stable-diffusion-3") ->
        {5.0, "euler"}

      # Chroma/Chroma1-Radiance models: cfg_scale 5.0, euler sampler
      String.contains?(model_lower, "chroma") ->
        {5.0, "euler"}

      # Default for other models
      true ->
        {7.0, "euler_a"}
    end
  end

  defp detect_model_defaults(_), do: {7.0, "euler_a"}

  # Materialize image to temp file if base64, return {path, temp_file_or_nil}
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

  # Cleanup temp files
  defp cleanup_temp_files(files) do
    Enum.each(files, fn file ->
      if file && File.exists?(file), do: File.rm(file)
    end)
  end
end
