defmodule LeaxerCore.Nodes.Detailer.DetailerForEach do
  @moduledoc """
  Enhance each detected segment (faces, hands, objects) using inpainting with seamless compositing.

  Works with any SEGS input - faces, hands, or any detected region.

  Accepts both base64 and path-based image inputs, returns base64 output.

  For each segment:
  1. Crop with padding (context around bbox)
  2. Create inpainting mask (from bbox rectangle or SAM segment mask)
  3. Resize crop and mask if > 2048px (UNet limit)
  4. SD inpainting (regenerates masked area, preserves context pixel-perfect)
  5. Resize back if needed
  6. Paste result with feathered blending

  Options:
  - `use_segment_mask`: When true, uses SAM segment mask instead of bbox rectangle.
    This gives more precise inpainting for irregular shapes like hands.

  Uses libvips for image processing (4-5x faster than ImageMagick).
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Workers.StableDiffusionServer
  alias LeaxerCore.Vips

  require Logger

  # Maximum dimension for SD processing - larger regions are resized down
  @max_sd_dimension 2048

  # Path to vips executable - bundled with the application
  defp vips_bin do
    tools_dir = Application.get_env(:leaxer_core, :tools_dir, "tools")
    Path.join([tools_dir, "vips-dev-8.18", "bin", "vips.exe"])
  end

  @impl true
  def type, do: "DetailerForEach"

  @impl true
  def label, do: "Detailer"

  @impl true
  def category, do: "Inference/Detailer"

  @impl true
  def description do
    "Enhance each detected segment by cropping, regenerating, and compositing back"
  end

  @impl true
  def input_spec do
    %{
      image: %{type: :image, label: "IMAGE"},
      segs: %{type: :segs, label: "SEGS"},
      model: %{type: :model, label: "MODEL"},
      positive: %{
        type: :string,
        label: "POSITIVE PROMPT",
        default: "highly detailed, sharp focus",
        multiline: true
      },
      negative: %{
        type: :string,
        label: "NEGATIVE PROMPT",
        default: "blurry, low quality, distorted",
        multiline: true
      },
      denoise: %{
        type: :float,
        label: "DENOISE",
        default: 0.4,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        description: "0.0 = no change, 1.0 = full regeneration"
      },
      steps: %{
        type: :integer,
        label: "STEPS",
        default: 20,
        min: 1,
        max: 100
      },
      cfg: %{
        type: :float,
        label: "CFG SCALE",
        default: 7.0,
        min: 1.0,
        max: 20.0,
        step: 0.5
      },
      seed: %{
        type: :integer,
        label: "SEED",
        default: -1,
        min: -1,
        max: 2_147_483_647,
        description: "-1 for random seed"
      },
      feather: %{
        type: :integer,
        label: "FEATHER %",
        default: 80,
        min: 0,
        max: 100,
        step: 5,
        description: "Feather as % of padding (80 = blur covers 80% of padding area)"
      },
      padding: %{
        type: :float,
        label: "PADDING",
        default: 0.5,
        min: 0.1,
        max: 1.0,
        step: 0.05,
        description: "Context padding around bbox (0.5 = 50%)"
      },
      use_segment_mask: %{
        type: :boolean,
        label: "USE SEGMENT MASK",
        default: false,
        description: "Use SAM segment mask instead of bbox rectangle for inpainting"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{type: :image, label: "IMAGE"},
      previews: %{type: {:list, :image}, label: "PREVIEWS"}
    }
  end

  @impl true
  def process(inputs, config) do
    # inputs = edge connections (image, segs, model)
    # config = node configured data (prompts, denoise, steps, etc.)
    segs = inputs["segs"]
    image = inputs["image"] || extract_segs_image(segs)
    model_path = extract_model_path(inputs["model"])

    # Read configured parameters from config, not inputs
    positive = config["positive"] || "highly detailed, sharp focus"
    negative = config["negative"] || "blurry, low quality, distorted"
    denoise = config["denoise"] || 0.4
    steps = config["steps"] || 20
    cfg = config["cfg"] || 7.0
    seed = config["seed"] || -1
    feather = config["feather"] || 16
    padding = config["padding"] || 0.25
    use_segment_mask = config["use_segment_mask"] || false

    with :ok <- validate_image(image),
         :ok <- validate_segs(segs),
         :ok <- validate_model(model_path) do
      # Materialize image to temp file if base64
      case Vips.materialize_to_temp(image) do
        {:ok, image_path} ->
          segments = segs["segments"] || []

          result =
            if length(segments) == 0 do
              # No segments - return original image as base64
              case read_as_base64(image_path) do
                {:ok, base64_image} -> {:ok, %{"image" => base64_image, "previews" => []}}
                {:error, reason} -> {:error, reason}
              end
            else
              opts = %{
                model: model_path,
                positive: positive,
                negative: negative,
                denoise: denoise,
                steps: steps,
                cfg: cfg,
                seed: seed,
                feather: feather,
                padding: padding,
                use_segment_mask: use_segment_mask,
                model_caching_strategy: config["model_caching_strategy"] || "auto"
              }

              # process_segments always returns {:ok, result_path, previews}
              {:ok, result_path, previews} = process_segments(image_path, segments, opts)

              # Convert result to base64
              case read_as_base64(result_path) do
                {:ok, base64_image} ->
                  # Convert previews to base64
                  base64_previews =
                    Enum.map(previews, fn preview_path ->
                      case read_as_base64(preview_path) do
                        {:ok, img} -> img
                        _ -> nil
                      end
                    end)
                    |> Enum.filter(& &1)

                  {:ok, %{"image" => base64_image, "previews" => base64_previews}}

                {:error, reason} ->
                  {:error, reason}
              end
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

  defp read_as_base64(path) do
    case File.read(path) do
      {:ok, binary} ->
        {:ok, %{data: Base.encode64(binary), mime_type: "image/png"}}

      {:error, reason} ->
        {:error, "Failed to read image: #{inspect(reason)}"}
    end
  end

  # Process segments sequentially, each modifies the current image
  defp process_segments(image_path, segments, opts) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    File.mkdir_p!(temp_dir)

    # Start with a copy of the original
    working_image =
      Path.join(temp_dir, "detailer_working_#{:erlang.unique_integer([:positive])}.png")

    File.cp!(image_path, working_image)

    {final_image, previews} =
      Enum.reduce(segments, {working_image, []}, fn seg, {current_image, acc_previews} ->
        case process_single_segment(current_image, seg, opts) do
          {:ok, enhanced_image, preview} ->
            {enhanced_image, acc_previews ++ [preview]}

          {:error, reason} ->
            Logger.warning("[Detailer] Failed to process segment: #{reason}")
            {current_image, acc_previews}
        end
      end)

    {:ok, final_image, Enum.filter(previews, & &1)}
  end

  defp process_single_segment(image_path, seg, opts) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    seg_id = seg["id"] || :erlang.unique_integer([:positive])
    uid = fn -> :erlang.unique_integer([:positive]) end

    [x1, y1, x2, y2] = seg["bbox"]
    bbox_w = x2 - x1
    bbox_h = y2 - y1

    Logger.info("[Detailer] Processing segment #{seg_id}: bbox #{x1},#{y1} #{bbox_w}x#{bbox_h}")

    # Get image dimensions for clamping padded region
    {img_w, img_h} = get_image_dimensions(image_path)

    # Calculate padded region (clamped to image bounds)
    pad_x = round(bbox_w * opts.padding)
    pad_y = round(bbox_h * opts.padding)

    px1 = max(0, x1 - pad_x)
    py1 = max(0, y1 - pad_y)
    px2 = min(img_w, x2 + pad_x)
    py2 = min(img_h, y2 + pad_y)
    padded_w = px2 - px1
    padded_h = py2 - py1

    # Inner bbox position relative to the padded crop
    inner_x = x1 - px1
    inner_y = y1 - py1

    # Calculate SD dimensions (rounded to 64) - this is what SD will actually output
    {sd_w, sd_h, _} = calculate_sd_dimensions(padded_w, padded_h)

    # Calculate scale factors for mapping positions between padded and SD space
    scale_x = sd_w / padded_w
    scale_y = sd_h / padded_h

    # Inner bbox in SD space (scaled)
    sd_inner_x = round(inner_x * scale_x)
    sd_inner_y = round(inner_y * scale_y)
    sd_bbox_w = round(bbox_w * scale_x)
    sd_bbox_h = round(bbox_h * scale_y)

    # Calculate feather based on SD dimensions
    sd_pad =
      Enum.min([
        sd_inner_x,
        sd_inner_y,
        sd_w - sd_inner_x - sd_bbox_w,
        sd_h - sd_inner_y - sd_bbox_h
      ])

    feather_ratio = opts.feather / 100.0
    effective_feather = max(8, round(sd_pad * feather_ratio * 1.5))

    Logger.info(
      "[Detailer] Crop: #{padded_w}x#{padded_h} at #{px1},#{py1} -> SD: #{sd_w}x#{sd_h}, feather=#{effective_feather}px"
    )

    # 1. Crop padded region
    crop_path = Path.join(temp_dir, "crop_#{seg_id}_#{uid.()}.png")
    crop_region(image_path, px1, py1, padded_w, padded_h, crop_path)

    # 2. Resize crop to SD dimensions
    sd_crop_path = Path.join(temp_dir, "sd_crop_#{seg_id}_#{uid.()}.png")
    resize_image(crop_path, sd_w, sd_h, sd_crop_path)

    # 3. Create inpainting mask at SD dimensions
    inpaint_blur = max(4, round(effective_feather / 4))
    mask_path = Path.join(temp_dir, "inpaint_mask_#{seg_id}_#{uid.()}.png")

    # Check if we should use segment mask (SAM) or bbox rectangle
    segment_mask = seg["mask"] || seg["segmentation"]
    use_seg_mask = opts.use_segment_mask && segment_mask != nil

    if use_seg_mask do
      # Use SAM segment mask - crop and resize to match SD dimensions
      create_mask_from_segment(
        segment_mask,
        px1,
        py1,
        padded_w,
        padded_h,
        sd_w,
        sd_h,
        inpaint_blur,
        mask_path
      )

      Logger.info("[Detailer] Using segment mask for inpainting")
    else
      # Use bbox rectangle mask
      create_inpaint_mask(
        sd_w,
        sd_h,
        sd_inner_x,
        sd_inner_y,
        sd_bbox_w,
        sd_bbox_h,
        inpaint_blur,
        mask_path
      )

      Logger.info("[Detailer] Using bbox rectangle for inpainting")
    end

    sd_input = sd_crop_path
    sd_mask = mask_path

    # 4. SD inpainting - regenerates white (masked) area with context from black areas
    sd_opts = [
      model: opts.model,
      negative_prompt: opts.negative,
      steps: opts.steps,
      cfg_scale: opts.cfg,
      width: sd_w,
      height: sd_h,
      seed: opts.seed,
      init_img: sd_input,
      mask: sd_mask,
      strength: opts.denoise,
      model_caching_strategy: opts.model_caching_strategy
    ]

    Logger.info("[Detailer] Running inpainting: #{sd_w}x#{sd_h}, denoise=#{opts.denoise}")

    case StableDiffusionServer.generate(opts.positive, sd_opts) do
      {:ok, result} ->
        Logger.info("[Detailer] SD completed: #{result.path}")

        # 5. Resize SD output back to original padded dimensions
        # This reverses the scale we applied to the input, keeping content aligned
        enhanced_padded = Path.join(temp_dir, "enhanced_#{seg_id}_#{uid.()}.png")
        resize_image(result.path, padded_w, padded_h, enhanced_padded)
        Logger.info("[Detailer] Resized SD output to #{padded_w}x#{padded_h}")

        # 6. Create feathered mask at padded dimensions (matches enhanced_padded)
        composite_mask_path = Path.join(temp_dir, "composite_mask_#{seg_id}_#{uid.()}.png")

        composite_feather =
          max(
            8,
            round(
              Enum.min([
                inner_x,
                inner_y,
                padded_w - inner_x - bbox_w,
                padded_h - inner_y - bbox_h
              ]) * feather_ratio * 1.5
            )
          )

        if use_seg_mask do
          # Use segment mask for compositing (crop from full mask, resize to padded dimensions)
          create_composite_mask_from_segment(
            segment_mask,
            px1,
            py1,
            padded_w,
            padded_h,
            composite_feather,
            composite_mask_path
          )
        else
          # Use bbox rectangle mask
          create_feather_mask_for_region(
            padded_w,
            padded_h,
            inner_x,
            inner_y,
            bbox_w,
            bbox_h,
            composite_feather,
            composite_mask_path
          )
        end

        # 7. Composite back onto original at correct position
        output_path = Path.join(temp_dir, "detailed_#{seg_id}_#{uid.()}.png")

        paste_with_feather(
          image_path,
          enhanced_padded,
          composite_mask_path,
          px1,
          py1,
          output_path
        )

        # Preview is the enhanced face area
        preview_path = Path.join(temp_dir, "preview_#{seg_id}_#{uid.()}.png")
        crop_region(enhanced_padded, inner_x, inner_y, bbox_w, bbox_h, preview_path)

        {:ok, output_path, preview_path}

      {:error, reason} ->
        Logger.error("[Detailer] SD failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Crop a region from image using vips (4-5x faster than ImageMagick)
  defp crop_region(image_path, x, y, w, h, output_path) do
    {_, 0} =
      System.cmd(vips_bin(), ["crop", image_path, output_path, "#{x}", "#{y}", "#{w}", "#{h}"])
  end

  # Resize image to exact dimensions using vips
  defp resize_image(input_path, target_w, target_h, output_path) do
    # Get current dimensions to calculate scale factors
    {curr_w, curr_h} = get_image_dimensions(input_path)
    scale_x = target_w / curr_w
    scale_y = target_h / curr_h

    # vips resize uses scale factor, vscale for independent vertical scaling
    {_, 0} =
      System.cmd(vips_bin(), [
        "resize",
        input_path,
        output_path,
        "#{scale_x}",
        "--vscale",
        "#{scale_y}",
        "--kernel",
        "lanczos3"
      ])
  end

  # Create inpainting mask: white=regenerate (face area), black=preserve (context)
  # Uses vips operations: black canvas -> white rectangle -> optional blur
  defp create_inpaint_mask(
         total_w,
         total_h,
         inner_x,
         inner_y,
         inner_w,
         inner_h,
         blur,
         output_path
       ) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    uid = :erlang.unique_integer([:positive])

    # 1. Create black canvas
    canvas_path = Path.join(temp_dir, "mask_canvas_#{uid}.png")
    {_, 0} = System.cmd(vips_bin(), ["black", canvas_path, "#{total_w}", "#{total_h}"])

    # 2. Create white rectangle
    white_rect_path = Path.join(temp_dir, "mask_white_#{uid}.png")
    {_, 0} = System.cmd(vips_bin(), ["black", white_rect_path, "#{inner_w}", "#{inner_h}"])
    white_filled_path = Path.join(temp_dir, "mask_white_filled_#{uid}.png")
    {_, 0} = System.cmd(vips_bin(), ["linear", white_rect_path, white_filled_path, "1", "255"])

    # 3. Insert white rectangle at inner position
    mask_raw_path = Path.join(temp_dir, "mask_raw_#{uid}.png")

    {_, 0} =
      System.cmd(vips_bin(), [
        "insert",
        canvas_path,
        white_filled_path,
        mask_raw_path,
        "#{inner_x}",
        "#{inner_y}"
      ])

    # 4. Apply blur if requested
    if blur > 0 do
      {_, 0} = System.cmd(vips_bin(), ["gaussblur", mask_raw_path, output_path, "#{blur}"])
    else
      File.cp!(mask_raw_path, output_path)
    end

    # Cleanup temp files
    Enum.each([canvas_path, white_rect_path, white_filled_path, mask_raw_path], &File.rm/1)
  end

  # Create inpainting mask from SAM segment mask
  # Crops the padded region from the full mask, resizes to SD dimensions
  defp create_mask_from_segment(
         segment_mask,
         px1,
         py1,
         padded_w,
         padded_h,
         sd_w,
         sd_h,
         blur,
         output_path
       ) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    uid = :erlang.unique_integer([:positive])

    # Handle mask input - could be file path or base64 data
    mask_source_path =
      case segment_mask do
        %{"path" => path} when is_binary(path) ->
          path

        # Likely a file path
        path when is_binary(path) and byte_size(path) < 500 ->
          path

        base64_data when is_binary(base64_data) ->
          # Decode base64 and save to temp file
          decoded = Base.decode64!(base64_data)
          tmp_path = Path.join(temp_dir, "seg_mask_src_#{uid}.png")
          File.write!(tmp_path, decoded)
          tmp_path

        _ ->
          Logger.warning("[Detailer] Unknown segment mask format")
          nil
      end

    if mask_source_path && File.exists?(mask_source_path) do
      # 1. Crop the padded region from the full-size mask
      cropped_mask_path = Path.join(temp_dir, "seg_mask_crop_#{uid}.png")
      crop_region(mask_source_path, px1, py1, padded_w, padded_h, cropped_mask_path)

      # 2. Resize to SD dimensions
      resized_mask_path = Path.join(temp_dir, "seg_mask_resized_#{uid}.png")
      resize_image(cropped_mask_path, sd_w, sd_h, resized_mask_path)

      # 3. Apply blur for soft edges if requested
      if blur > 0 do
        {_, 0} = System.cmd(vips_bin(), ["gaussblur", resized_mask_path, output_path, "#{blur}"])
      else
        File.cp!(resized_mask_path, output_path)
      end

      # Cleanup
      File.rm(cropped_mask_path)
      File.rm(resized_mask_path)
    else
      # Fallback: create empty white mask (will regenerate entire region)
      Logger.warning("[Detailer] Segment mask not found, using full region")
      {_, 0} = System.cmd(vips_bin(), ["black", output_path, "#{sd_w}", "#{sd_h}"])
      {_, 0} = System.cmd(vips_bin(), ["linear", output_path, output_path, "1", "255"])
    end
  end

  # Create composite mask from SAM segment for the padded region
  defp create_composite_mask_from_segment(
         segment_mask,
         px1,
         py1,
         padded_w,
         padded_h,
         feather,
         output_path
       ) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    uid = :erlang.unique_integer([:positive])

    # Handle mask input
    mask_source_path =
      case segment_mask do
        %{"path" => path} when is_binary(path) ->
          path

        path when is_binary(path) and byte_size(path) < 500 ->
          path

        base64_data when is_binary(base64_data) ->
          decoded = Base.decode64!(base64_data)
          tmp_path = Path.join(temp_dir, "comp_mask_src_#{uid}.png")
          File.write!(tmp_path, decoded)
          tmp_path

        _ ->
          nil
      end

    if mask_source_path && File.exists?(mask_source_path) do
      # 1. Crop the padded region from the full-size mask
      cropped_mask_path = Path.join(temp_dir, "comp_mask_crop_#{uid}.png")
      crop_region(mask_source_path, px1, py1, padded_w, padded_h, cropped_mask_path)

      # 2. Apply feather blur
      if feather > 0 do
        {_, 0} =
          System.cmd(vips_bin(), ["gaussblur", cropped_mask_path, output_path, "#{feather}"])
      else
        File.cp!(cropped_mask_path, output_path)
      end

      File.rm(cropped_mask_path)
    else
      # Fallback: create white mask
      {_, 0} = System.cmd(vips_bin(), ["black", output_path, "#{padded_w}", "#{padded_h}"])
      {_, 0} = System.cmd(vips_bin(), ["linear", output_path, output_path, "1", "255"])
    end
  end

  # Create feathered compositing mask for a padded region
  # White in the inner bbox area, fading to black at the padded edges
  defp create_feather_mask_for_region(
         total_w,
         total_h,
         inner_x,
         inner_y,
         inner_w,
         inner_h,
         feather,
         output_path
       ) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    uid = :erlang.unique_integer([:positive])

    # 1. Create black canvas
    canvas_path = Path.join(temp_dir, "feather_canvas_#{uid}.png")
    {_, 0} = System.cmd(vips_bin(), ["black", canvas_path, "#{total_w}", "#{total_h}"])

    # 2. Create white rectangle
    white_rect_path = Path.join(temp_dir, "feather_white_#{uid}.png")
    {_, 0} = System.cmd(vips_bin(), ["black", white_rect_path, "#{inner_w}", "#{inner_h}"])
    white_filled_path = Path.join(temp_dir, "feather_white_filled_#{uid}.png")
    {_, 0} = System.cmd(vips_bin(), ["linear", white_rect_path, white_filled_path, "1", "255"])

    # 3. Insert white rectangle at inner position
    mask_raw_path = Path.join(temp_dir, "feather_raw_#{uid}.png")

    {_, 0} =
      System.cmd(vips_bin(), [
        "insert",
        canvas_path,
        white_filled_path,
        mask_raw_path,
        "#{inner_x}",
        "#{inner_y}"
      ])

    # 4. Apply gaussian blur for feathering
    if feather > 0 do
      {_, 0} = System.cmd(vips_bin(), ["gaussblur", mask_raw_path, output_path, "#{feather}"])
    else
      File.cp!(mask_raw_path, output_path)
    end

    # Cleanup temp files
    Enum.each([canvas_path, white_rect_path, white_filled_path, mask_raw_path], &File.rm/1)
  end

  # Paste crop onto image using feathered mask for smooth alpha blending
  # Uses vips embed + ifthenelse --blend for smooth compositing
  defp paste_with_feather(image_path, crop_path, mask_path, x, y, output_path) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    uid = :erlang.unique_integer([:positive])

    # Get full image dimensions
    {full_w, full_h} = get_image_dimensions(image_path)

    # 1. Embed crop into full-size canvas at position (x, y)
    crop_embedded_path = Path.join(temp_dir, "crop_embed_#{uid}.png")

    {_, 0} =
      System.cmd(vips_bin(), [
        "embed",
        crop_path,
        crop_embedded_path,
        "#{x}",
        "#{y}",
        "#{full_w}",
        "#{full_h}",
        "--extend",
        "black"
      ])

    # 2. Embed mask into full-size canvas at position (x, y)
    mask_embedded_path = Path.join(temp_dir, "mask_embed_#{uid}.png")

    {_, 0} =
      System.cmd(vips_bin(), [
        "embed",
        mask_path,
        mask_embedded_path,
        "#{x}",
        "#{y}",
        "#{full_w}",
        "#{full_h}",
        "--extend",
        "black"
      ])

    # 3. Use ifthenelse with blend to smoothly composite
    # Where mask is white (255), use crop; where black (0), use original
    {_, 0} =
      System.cmd(vips_bin(), [
        "ifthenelse",
        mask_embedded_path,
        crop_embedded_path,
        image_path,
        output_path,
        "--blend"
      ])

    # Cleanup
    File.rm(crop_embedded_path)
    File.rm(mask_embedded_path)
  end

  # Calculate SD dimensions, respecting max size limit
  # Returns {sd_width, sd_height, needs_resize}
  defp calculate_sd_dimensions(width, height) do
    max_dim = max(width, height)

    if max_dim <= @max_sd_dimension do
      {round_to_64(width), round_to_64(height), false}
    else
      scale = @max_sd_dimension / max_dim
      scaled_w = round(width * scale)
      scaled_h = round(height * scale)
      {round_to_64(scaled_w), round_to_64(scaled_h), true}
    end
  end

  defp round_to_64(value) do
    div(value + 63, 64) * 64
  end

  # Extract image from SEGS (new format uses "image", legacy uses "image_path")
  defp extract_segs_image(%{"image" => image}), do: image
  defp extract_segs_image(%{"image_path" => path}) when is_binary(path), do: %{path: path}
  defp extract_segs_image(_), do: nil

  # Extract model path from model object
  defp extract_model_path(%{path: path}) when is_binary(path), do: path
  defp extract_model_path(%{"path" => path}) when is_binary(path), do: path
  defp extract_model_path(path) when is_binary(path), do: path
  defp extract_model_path(_), do: nil

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
  defp validate_segs(%{"segments" => segs}) when is_list(segs), do: :ok
  defp validate_segs(_), do: {:error, "Invalid SEGS format"}

  defp validate_model(nil), do: {:error, "Model is required for detailing"}

  defp validate_model(path) when is_binary(path) do
    if File.exists?(path), do: :ok, else: {:error, "Model not found: #{path}"}
  end

  defp validate_model(_), do: {:error, "Invalid model input"}

  # Get image dimensions using vipsheader (faster than ImageMagick identify)
  defp get_image_dimensions(image_path) do
    vipsheader =
      Path.join([
        Application.get_env(:leaxer_core, :tools_dir, "tools"),
        "vips-dev-8.18",
        "bin",
        "vipsheader.exe"
      ])

    {output, 0} = System.cmd(vipsheader, ["-f", "width", image_path])
    width = output |> String.trim() |> String.to_integer()
    {output, 0} = System.cmd(vipsheader, ["-f", "height", image_path])
    height = output |> String.trim() |> String.to_integer()
    {width, height}
  end
end
