defmodule LeaxerCore.Nodes.Detailer.SEGSCombine do
  @moduledoc """
  Combine multiple SEGS into one.

  Useful for merging detections from different sources:
  - Combine face and hand detections
  - Merge results from multiple detection passes
  - Union different object types for batch processing

  ## Combine Modes
  - **Concatenate**: Simply join all segments together
  - **Remove duplicates**: Remove overlapping segments (by IoU threshold)
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "SEGSCombine"

  @impl true
  def label, do: "SEGS Combine"

  @impl true
  def category, do: "Inference/Segmentation"

  @impl true
  def description do
    "Combine multiple SEGS into one"
  end

  @impl true
  def input_spec do
    %{
      segs_a: %{type: :segs, label: "SEGS"},
      segs_b: %{type: :segs, label: "SEGS"},
      mode: %{
        type: :enum,
        label: "MODE",
        default: "concatenate",
        options: [
          %{value: "concatenate", label: "Concatenate (keep all)"},
          %{value: "deduplicate", label: "Remove duplicates (by IoU)"}
        ]
      },
      iou_threshold: %{
        type: :float,
        label: "IOU THRESHOLD",
        default: 0.5,
        min: 0.1,
        max: 1.0,
        step: 0.1,
        description: "Overlap threshold for duplicate removal"
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
    # inputs = edge connections (segs_a, segs_b)
    # config = node configured data (mode, iou_threshold)
    segs_a = inputs["segs_a"]
    segs_b = inputs["segs_b"]
    mode = config["mode"] || "concatenate"
    iou_threshold = config["iou_threshold"] || 0.5

    with :ok <- validate_segs(segs_a, "SEGS A"),
         :ok <- validate_segs(segs_b, "SEGS B") do
      # Use shape from first SEGS (they should match)
      shape = segs_a["shape"] || segs_b["shape"]

      segments_a = segs_a["segments"] || []
      segments_b = segs_b["segments"] || []

      combined =
        case mode do
          "concatenate" ->
            concatenate_segments(segments_a, segments_b)

          "deduplicate" ->
            deduplicate_segments(segments_a, segments_b, iou_threshold)

          _ ->
            concatenate_segments(segments_a, segments_b)
        end

      {:ok,
       %{
         "segs" => %{
           "shape" => shape,
           "segments" => combined
         }
       }}
    end
  end

  defp validate_segs(nil, name), do: {:error, "#{name} is required"}
  defp validate_segs(%{"segments" => _}, _name), do: :ok
  defp validate_segs(_, name), do: {:error, "Invalid #{name} format"}

  defp concatenate_segments(segments_a, segments_b) do
    (segments_a ++ segments_b)
    |> Enum.with_index()
    |> Enum.map(fn {seg, idx} -> Map.put(seg, "id", idx) end)
  end

  defp deduplicate_segments(segments_a, segments_b, iou_threshold) do
    all_segments = segments_a ++ segments_b

    # Sort by confidence descending
    sorted = Enum.sort_by(all_segments, & &1["confidence"], :desc)

    # Non-maximum suppression
    {kept, _} =
      Enum.reduce(sorted, {[], []}, fn seg, {kept, rejected} ->
        # Check if this segment overlaps too much with any kept segment
        dominated =
          Enum.any?(kept, fn kept_seg ->
            iou(seg["bbox"], kept_seg["bbox"]) > iou_threshold
          end)

        if dominated do
          {kept, [seg | rejected]}
        else
          {kept ++ [seg], rejected}
        end
      end)

    # Re-index
    kept
    |> Enum.with_index()
    |> Enum.map(fn {seg, idx} -> Map.put(seg, "id", idx) end)
  end

  defp iou(bbox_a, bbox_b) do
    [ax1, ay1, ax2, ay2] = bbox_a
    [bx1, by1, bx2, by2] = bbox_b

    # Intersection
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)

    if ix2 <= ix1 || iy2 <= iy1 do
      0.0
    else
      intersection = (ix2 - ix1) * (iy2 - iy1)
      area_a = (ax2 - ax1) * (ay2 - ay1)
      area_b = (bx2 - bx1) * (by2 - by1)
      union = area_a + area_b - intersection

      if union > 0 do
        intersection / union
      else
        0.0
      end
    end
  end
end
