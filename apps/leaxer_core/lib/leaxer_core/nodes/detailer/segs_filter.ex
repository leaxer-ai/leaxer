defmodule LeaxerCore.Nodes.Detailer.SEGSFilter do
  @moduledoc """
  Filter segments by various criteria.

  Use this to select only segments that meet certain conditions:
  - Confidence threshold
  - Size constraints (min/max area)
  - Label matching
  - Count limits (top N)

  ## Use Cases
  - Keep only high-confidence detections
  - Filter out tiny or huge detections
  - Select only faces, ignore other detections
  - Process only the largest N detections
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "SEGSFilter"

  @impl true
  def label, do: "SEGS Filter"

  @impl true
  def category, do: "Inference/Segmentation"

  @impl true
  def description do
    "Filter segments by confidence, size, label, or count"
  end

  @impl true
  def input_spec do
    %{
      segs: %{type: :segs, label: "SEGS"},
      min_confidence: %{
        type: :float,
        label: "MIN CONFIDENCE",
        default: 0.0,
        min: 0.0,
        max: 1.0,
        step: 0.05
      },
      max_confidence: %{
        type: :float,
        label: "MAX CONFIDENCE",
        default: 1.0,
        min: 0.0,
        max: 1.0,
        step: 0.05
      },
      min_area: %{
        type: :integer,
        label: "MIN AREA",
        default: 0,
        min: 0,
        max: 1_000_000,
        description: "Minimum bounding box area in pixels"
      },
      max_area: %{
        type: :integer,
        label: "MAX AREA",
        default: 0,
        min: 0,
        max: 10_000_000,
        description: "Maximum bounding box area (0 = no limit)"
      },
      labels: %{
        type: :string,
        label: "LABELS",
        default: "",
        description: "Only keep segments with these labels (empty = all)"
      },
      max_count: %{
        type: :integer,
        label: "MAX COUNT",
        default: 0,
        min: 0,
        max: 100,
        description: "Keep only top N by confidence (0 = no limit)"
      },
      sort_by: %{
        type: :enum,
        label: "SORT BY",
        default: "confidence",
        options: [
          %{value: "confidence", label: "Confidence (high to low)"},
          %{value: "area", label: "Area (large to small)"},
          %{value: "position", label: "Position (left to right)"}
        ]
      }
    }
  end

  @impl true
  def output_spec do
    %{
      segs: %{type: :segs, label: "SEGS"},
      rejected: %{type: :segs, label: "SEGS"}
    }
  end

  @impl true
  def process(inputs, config) do
    # inputs = edge connections (segs)
    # config = node configured data (thresholds, filters, etc.)
    segs = inputs["segs"]
    min_confidence = config["min_confidence"] || 0.0
    max_confidence = config["max_confidence"] || 1.0
    min_area = config["min_area"] || 0
    max_area = config["max_area"] || 0
    labels_str = config["labels"] || ""
    max_count = config["max_count"] || 0
    sort_by = config["sort_by"] || "confidence"

    with :ok <- validate_segs(segs) do
      segments = segs["segments"] || []

      # Parse labels
      allowed_labels =
        if labels_str == "" do
          nil
        else
          labels_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
        end

      # Filter segments
      {accepted, rejected} =
        segments
        |> Enum.split_with(fn seg ->
          confidence = seg["confidence"] || 0
          [x1, y1, x2, y2] = seg["bbox"]
          area = (x2 - x1) * (y2 - y1)
          label = seg["label"] || ""

          passes_confidence = confidence >= min_confidence && confidence <= max_confidence
          passes_min_area = area >= min_area
          passes_max_area = max_area == 0 || area <= max_area
          passes_label = allowed_labels == nil || label in allowed_labels

          passes_confidence && passes_min_area && passes_max_area && passes_label
        end)

      # Sort accepted segments
      sorted =
        case sort_by do
          "confidence" ->
            Enum.sort_by(accepted, & &1["confidence"], :desc)

          "area" ->
            Enum.sort_by(
              accepted,
              fn seg ->
                [x1, y1, x2, y2] = seg["bbox"]
                (x2 - x1) * (y2 - y1)
              end,
              :desc
            )

          "position" ->
            Enum.sort_by(accepted, fn seg ->
              [x1, _y1, _x2, _y2] = seg["bbox"]
              x1
            end)

          _ ->
            accepted
        end

      # Apply max count
      final =
        if max_count > 0 do
          {kept, extra_rejected} = Enum.split(sorted, max_count)
          {kept, rejected ++ extra_rejected}
        else
          {sorted, rejected}
        end

      {accepted_segs, rejected_segs} = final

      # Re-index segments
      accepted_segs =
        accepted_segs
        |> Enum.with_index()
        |> Enum.map(fn {seg, idx} -> Map.put(seg, "id", idx) end)

      {:ok,
       %{
         "segs" => Map.put(segs, "segments", accepted_segs),
         "rejected" => Map.put(segs, "segments", rejected_segs)
       }}
    end
  end

  defp validate_segs(nil), do: {:error, "SEGS is required"}
  defp validate_segs(%{"segments" => _}), do: :ok
  defp validate_segs(_), do: {:error, "Invalid SEGS format"}
end
