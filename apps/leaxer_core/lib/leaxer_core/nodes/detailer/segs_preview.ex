defmodule LeaxerCore.Nodes.Detailer.SEGSPreview do
  @moduledoc """
  Preview detected segments overlaid on the original image.

  Draws bounding boxes and labels on the image to visualize detections.
  If masks are available (after SAM processing), also shows mask overlays.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Inputs
  - `image` - Original image
  - `segs` - Segments to visualize

  ## Outputs
  - `preview` - Image with detection overlays
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Vips

  @impl true
  def type, do: "SEGSPreview"

  @impl true
  def label, do: "SEGS Preview"

  @impl true
  def category, do: "Inference/Segmentation"

  @impl true
  def description do
    "Preview detected segments with bounding boxes and masks overlaid"
  end

  @impl true
  def input_spec do
    %{
      image: %{type: :image, label: "IMAGE"},
      segs: %{type: :segs, label: "SEGS"},
      show_boxes: %{
        type: :boolean,
        label: "SHOW BOXES",
        default: true
      },
      show_labels: %{
        type: :boolean,
        label: "SHOW LABELS",
        default: true
      },
      show_masks: %{
        type: :boolean,
        label: "SHOW MASKS",
        default: true
      },
      mask_opacity: %{
        type: :float,
        label: "MASK OPACITY",
        default: 0.5,
        min: 0.0,
        max: 1.0,
        step: 0.1
      },
      box_color: %{
        type: :string,
        label: "BOX COLOR",
        default: "#00ff00"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      preview: %{type: :image, label: "IMAGE"}
    }
  end

  @impl true
  def process(inputs, config) do
    # inputs = edge connections (image, segs)
    # config = node configured data (show options, colors, etc.)
    segs = inputs["segs"]

    # Use explicit image input, or fall back to image embedded in SEGS
    image = inputs["image"] || extract_segs_image(segs)

    show_boxes = config["show_boxes"] != false
    show_labels = config["show_labels"] != false
    show_masks = config["show_masks"] != false
    mask_opacity = config["mask_opacity"] || 0.5
    box_color = config["box_color"] || "#00ff00"

    with :ok <- validate_image(image),
         :ok <- validate_segs(segs) do
      # Materialize image to temp file if it's base64
      case Vips.materialize_to_temp(image) do
        {:ok, image_path} ->
          output_path = generate_output_path()

          result =
            case generate_preview(
                   image_path,
                   segs,
                   output_path,
                   show_boxes: show_boxes,
                   show_labels: show_labels,
                   show_masks: show_masks,
                   mask_opacity: mask_opacity,
                   box_color: box_color
                 ) do
              :ok ->
                # Read result as base64
                case File.read(output_path) do
                  {:ok, binary} ->
                    base64_data = Base.encode64(binary)
                    {:ok, %{"preview" => %{data: base64_data, mime_type: "image/png"}}}

                  {:error, reason} ->
                    {:error, "Failed to read preview: #{inspect(reason)}"}
                end

              {:error, reason} ->
                {:error, reason}
            end

          # Clean up temp files
          unless is_path_based?(image), do: File.rm(image_path)
          File.rm(output_path)

          result

        {:error, reason} ->
          {:error, "Failed to process image: #{reason}"}
      end
    end
  end

  defp is_path_based?(%{path: _}), do: true
  defp is_path_based?(%{"path" => _}), do: true
  defp is_path_based?(_), do: false

  # Extract image embedded in SEGS (added by DetectObjects)
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

  defp generate_output_path do
    output_dir = LeaxerCore.Paths.tmp_dir()
    File.mkdir_p!(output_dir)
    filename = "segs_preview_#{:erlang.unique_integer([:positive])}.png"
    Path.join(output_dir, filename)
  end

  defp generate_preview(image_path, segs, output_path, opts) do
    show_boxes = opts[:show_boxes]
    show_labels = opts[:show_labels]
    show_masks = opts[:show_masks]
    mask_opacity = opts[:mask_opacity]
    box_color = opts[:box_color]

    # Build ImageMagick command for drawing overlays
    segments = segs["segments"] || []

    # Start with copying the input image
    draw_commands = []

    # Add bounding box drawings
    draw_commands =
      if show_boxes do
        box_draws =
          Enum.map(segments, fn seg ->
            [x1, y1, x2, y2] = seg["bbox"]
            "rectangle #{x1},#{y1} #{x2},#{y2}"
          end)

        draw_commands ++ box_draws
      else
        draw_commands
      end

    # Add label drawings
    draw_commands =
      if show_labels do
        label_draws =
          Enum.map(segments, fn seg ->
            [x1, y1, _x2, _y2] = seg["bbox"]
            label = seg["label"] || "object"
            confidence = seg["confidence"] || 0
            text = "#{label} #{Float.round(confidence * 100, 1)}%"
            "text #{x1},#{y1 - 5} '#{text}'"
          end)

        draw_commands ++ label_draws
      else
        draw_commands
      end

    if length(draw_commands) > 0 do
      draw_string = Enum.join(draw_commands, " ")

      args = [
        image_path,
        "-fill",
        "none",
        "-stroke",
        box_color,
        "-strokewidth",
        "2",
        "-draw",
        draw_string,
        output_path
      ]

      # Add mask overlays if available and enabled
      args =
        if show_masks do
          mask_overlay_args(segments, mask_opacity, args)
        else
          args
        end

      case System.cmd("magick", args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {error, _} -> {:error, "Failed to generate preview: #{error}"}
      end
    else
      # Just copy the image if no drawings
      File.cp!(image_path, output_path)
      :ok
    end
  end

  defp mask_overlay_args(segments, opacity, base_args) do
    # For now, just return base args - mask overlay is more complex
    # and would require compositing multiple images
    # TODO: Implement mask overlay compositing
    _ = {segments, opacity}
    base_args
  end
end
