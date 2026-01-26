defmodule LeaxerCore.Nodes.Detailer.SEGSToMask do
  @moduledoc """
  Convert SEGS to a mask image.

  Creates a single mask image from all segments. Useful for:
  - Using detection results with any mask-based workflow
  - Video rotoscoping (detect → mask → composite)
  - Inpainting with standard tools
  - Selective effects application

  Returns base64 output.

  ## Outputs
  - White (255) = detected regions
  - Black (0) = background
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "SEGSToMask"

  @impl true
  def label, do: "SEGS to Mask"

  @impl true
  def category, do: "Inference/Segmentation"

  @impl true
  def description do
    "Convert detected segments to a mask image"
  end

  @impl true
  def input_spec do
    %{
      segs: %{type: :segs, label: "SEGS"},
      use_bbox: %{
        type: :boolean,
        label: "USE BBOX",
        default: false,
        description: "Use bounding boxes instead of masks (if no masks available)"
      },
      combine_mode: %{
        type: :enum,
        label: "COMBINE MODE",
        default: "add",
        options: [
          %{value: "add", label: "Add (union)"},
          %{value: "subtract", label: "Subtract"},
          %{value: "intersect", label: "Intersect"}
        ]
      },
      feather: %{
        type: :integer,
        label: "FEATHER",
        default: 0,
        min: 0,
        max: 64,
        step: 4,
        description: "Blur mask edges"
      },
      expand: %{
        type: :integer,
        label: "EXPAND",
        default: 0,
        min: -64,
        max: 64,
        step: 4,
        description: "Positive = expand mask, negative = contract"
      },
      invert: %{
        type: :boolean,
        label: "INVERT",
        default: false
      }
    }
  end

  @impl true
  def output_spec do
    %{
      mask: %{type: :mask, label: "MASK"}
    }
  end

  @impl true
  def process(inputs, config) do
    # inputs = edge connections (segs)
    # config = node configured data (use_bbox, feather, etc.)
    segs = inputs["segs"]
    use_bbox = config["use_bbox"] == true
    _combine_mode = config["combine_mode"] || "add"
    feather = config["feather"] || 0
    expand = config["expand"] || 0
    invert = config["invert"] == true

    with :ok <- validate_segs(segs) do
      [height, width] = segs["shape"]
      segments = segs["segments"] || []

      output_path = generate_output_path()

      create_mask(width, height, segments, output_path, use_bbox, feather, expand, invert)

      # Read result as base64
      case File.read(output_path) do
        {:ok, binary} ->
          base64_data = Base.encode64(binary)
          File.rm(output_path)
          {:ok, %{"mask" => %{data: base64_data, mime_type: "image/png"}}}

        {:error, reason} ->
          {:error, "Failed to read mask: #{inspect(reason)}"}
      end
    end
  end

  defp validate_segs(nil), do: {:error, "SEGS is required"}
  defp validate_segs(%{"segments" => _, "shape" => _}), do: :ok
  defp validate_segs(%{"segments" => _}), do: {:error, "SEGS missing shape information"}
  defp validate_segs(_), do: {:error, "Invalid SEGS format"}

  defp generate_output_path do
    output_dir = LeaxerCore.Paths.tmp_dir()
    File.mkdir_p!(output_dir)
    filename = "mask_#{:erlang.unique_integer([:positive])}.png"
    Path.join(output_dir, filename)
  end

  defp create_mask(width, height, segments, output_path, use_bbox, feather, expand, invert) do
    _temp_dir = LeaxerCore.Paths.tmp_dir()

    # Create black canvas
    System.cmd("magick", [
      "-size",
      "#{width}x#{height}",
      "xc:black",
      output_path
    ])

    # Add each segment to the mask
    Enum.each(segments, fn seg ->
      if use_bbox || seg["mask_path"] == nil do
        # Draw rectangle for bounding box
        [x1, y1, x2, y2] = seg["bbox"]

        System.cmd("magick", [
          output_path,
          "-fill",
          "white",
          "-draw",
          "rectangle #{x1},#{y1} #{x2},#{y2}",
          output_path
        ])
      else
        # Composite the segment mask
        if File.exists?(seg["mask_path"]) do
          [x1, y1, _x2, _y2] = seg["crop_region"] || seg["bbox"]

          System.cmd("magick", [
            output_path,
            seg["mask_path"],
            "-geometry",
            "+#{x1}+#{y1}",
            "-compose",
            "Lighten",
            "-composite",
            output_path
          ])
        end
      end
    end)

    # Apply expand/contract
    if expand != 0 do
      if expand > 0 do
        System.cmd("magick", [
          output_path,
          "-morphology",
          "Dilate",
          "Disk:#{expand}",
          output_path
        ])
      else
        System.cmd("magick", [
          output_path,
          "-morphology",
          "Erode",
          "Disk:#{abs(expand)}",
          output_path
        ])
      end
    end

    # Apply feather
    if feather > 0 do
      System.cmd("magick", [
        output_path,
        "-blur",
        "0x#{feather}",
        output_path
      ])
    end

    # Apply invert
    if invert do
      System.cmd("magick", [
        output_path,
        "-negate",
        output_path
      ])
    end

    :ok
  end
end
