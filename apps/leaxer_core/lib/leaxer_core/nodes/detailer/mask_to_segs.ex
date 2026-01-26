defmodule LeaxerCore.Nodes.Detailer.MaskToSEGS do
  @moduledoc """
  Convert a mask image to SEGS format.

  Takes a binary mask and finds connected regions, converting them to segments.
  Useful for:
  - Using hand-drawn masks with the detailer pipeline
  - Converting external masks to SEGS
  - Creating segments from threshold operations

  Accepts both base64 and path-based mask inputs.

  ## Input
  - Mask image where white (255) = regions of interest

  ## Output
  - SEGS with bounding boxes and mask data for each connected region

  Note: Uses ImageMagick for connected-components analysis as vips doesn't provide
  verbose output with bounding boxes and areas.
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Vips

  @impl true
  def type, do: "MaskToSEGS"

  @impl true
  def label, do: "Mask to SEGS"

  @impl true
  def category, do: "Inference/Segmentation"

  @impl true
  def description do
    "Convert a mask image to SEGS format (segments with bounding boxes)"
  end

  @impl true
  def input_spec do
    %{
      mask: %{type: :mask, label: "MASK"},
      min_area: %{
        type: :integer,
        label: "MIN AREA",
        default: 100,
        min: 1,
        max: 100_000,
        description: "Minimum region area in pixels"
      },
      threshold: %{
        type: :integer,
        label: "THRESHOLD",
        default: 128,
        min: 1,
        max: 255,
        description: "Pixel value threshold for mask"
      },
      label: %{
        type: :string,
        label: "LABEL",
        default: "region",
        description: "Label to assign to detected regions"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      segs: %{type: :segs, label: "SEGS"}
    }
  end

  @impl true
  def process(inputs, config) do
    mask = inputs["mask"]
    min_area = config["min_area"] || 100
    threshold = config["threshold"] || 128
    label = config["label"] || "region"

    if is_nil(mask) do
      {:error, "Mask is required"}
    else
      # Materialize mask to temp file if it's base64
      case Vips.materialize_to_temp(mask) do
        {:ok, mask_path} ->
          result = find_regions(mask_path, min_area, threshold, label, mask)

          # Clean up temp file if we materialized from base64
          unless is_path_based?(mask) do
            File.rm(mask_path)
          end

          result

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp is_path_based?(%{path: _}), do: true
  defp is_path_based?(%{"path" => _}), do: true
  defp is_path_based?(_), do: false

  defp find_regions(mask_path, min_area, threshold, label, _original_mask) do
    temp_dir = LeaxerCore.Paths.tmp_dir()
    File.mkdir_p!(temp_dir)

    # Get image dimensions using vips
    case Vips.identify(%{path: mask_path}) do
      {:ok, %{width: width, height: height}} ->
        # Threshold the mask to binary
        binary_mask = Path.join(temp_dir, "binary_#{:erlang.unique_integer([:positive])}.png")

        # Use ImageMagick for threshold since we need it for connected-components anyway
        case System.cmd("magick", [
               mask_path,
               "-threshold",
               "#{threshold / 255 * 100}%",
               binary_mask
             ]) do
          {_, 0} ->
            # Use connected components analysis to find regions
            {cc_output, _} =
              System.cmd("magick", [
                binary_mask,
                "-define",
                "connected-components:verbose=true",
                "-define",
                "connected-components:mean-color=true",
                "-define",
                "connected-components:area-threshold=#{min_area}",
                "-connected-components",
                "8",
                "-auto-level",
                "null:"
              ])

            # Parse connected components output
            segments =
              cc_output
              |> String.split("\n")
              |> Enum.filter(&String.contains?(&1, "srgb(255,255,255)"))
              |> Enum.map(&parse_cc_line/1)
              |> Enum.filter(&(&1 != nil))
              |> Enum.filter(fn seg -> seg.area >= min_area end)
              |> Enum.with_index()
              |> Enum.map(fn {seg, idx} ->
                # Extract region mask as base64
                [x1, y1, x2, y2] = seg.bbox
                region_w = x2 - x1
                region_h = y2 - y1

                # Crop the region mask using vips
                mask_result =
                  case Vips.crop(%{path: binary_mask}, x1, y1, region_w, region_h) do
                    {:ok, cropped_mask} ->
                      cropped_mask

                    {:error, _} ->
                      # Fallback: create a white mask of the region size
                      case Vips.create_canvas(region_w, region_h, color: "255 255 255") do
                        {:ok, white_mask} -> white_mask
                        {:error, _} -> nil
                      end
                  end

                %{
                  "id" => idx,
                  "label" => label,
                  "confidence" => 1.0,
                  "bbox" => seg.bbox,
                  "crop_region" => seg.bbox,
                  "mask" => mask_result,
                  "area" => seg.area
                }
              end)
              |> Enum.filter(fn seg -> seg["mask"] != nil end)

            # Cleanup
            File.rm(binary_mask)

            {:ok,
             %{
               "segs" => %{
                 "shape" => [height, width],
                 "segments" => segments
               }
             }}

          {error, code} ->
            Logger.error("ImageMagick threshold failed (exit #{code}): #{error}")
            {:error, "Failed to threshold mask"}
        end

      {:error, reason} ->
        {:error, "Failed to get mask dimensions: #{reason}"}
    end
  end

  defp parse_cc_line(line) do
    # Example line: "  42: 100x80+50+60 srgb(255,255,255) 8000 129.5,99.5"
    case Regex.run(~r/(\d+)x(\d+)\+(\d+)\+(\d+).*?(\d+)\s+[\d.]+,[\d.]+$/, line) do
      [_, w, h, x, y, area] ->
        x = String.to_integer(x)
        y = String.to_integer(y)
        w = String.to_integer(w)
        h = String.to_integer(h)

        %{
          bbox: [x, y, x + w, y + h],
          area: String.to_integer(area)
        }

      _ ->
        nil
    end
  end
end
