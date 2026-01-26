defmodule LeaxerCore.Nodes.Detailer.GroundingDinoLoader do
  @moduledoc """
  Loads a GroundingDINO model for object detection.

  GroundingDINO enables text-prompted object detection - describe what you want
  to find (e.g., "face", "hand", "red car") and it returns bounding boxes.

  ## Output
  - `detector` - Loaded detector configuration for use with DetectObjects node
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "GroundingDinoLoader"

  @impl true
  def label, do: "GroundingDINO Loader"

  @impl true
  def category, do: "Inference/Detection"

  @impl true
  def description do
    "Load a GroundingDINO model for text-prompted object detection"
  end

  @impl true
  def input_spec do
    %{
      model_name: %{
        type: :enum,
        label: "MODEL",
        default: "groundingdino_swint_ogc",
        options: [
          %{value: "groundingdino_swint_ogc", label: "Swin-T (341MB, Fast)"},
          %{value: "groundingdino_swinb_cogcoor", label: "Swin-B (694MB, Better)"}
        ]
      }
    }
  end

  @impl true
  def output_spec do
    %{
      detector: %{type: :detector, label: "DETECTOR"}
    }
  end

  @impl true
  def process(inputs, config) do
    model_name = inputs["model_name"] || config["model_name"] || "groundingdino_swint_ogc"

    # Return a detector configuration (actual loading happens in DetectObjects)
    detector = %{
      "type" => "grounding_dino",
      "model_name" => model_name,
      "loaded" => true
    }

    {:ok, %{"detector" => detector}}
  end
end
