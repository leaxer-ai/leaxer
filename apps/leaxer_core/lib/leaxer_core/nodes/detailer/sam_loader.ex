defmodule LeaxerCore.Nodes.Detailer.SAMLoader do
  @moduledoc """
  Loads a Segment Anything Model (SAM) for precise mask generation.

  SAM creates pixel-perfect masks from bounding boxes or point prompts.
  Different models offer trade-offs between speed and quality.

  ## Models
  - **MobileSAM** (40MB) - Fast, good for real-time applications
  - **SAM ViT-B** (375MB) - Good balance of speed and quality
  - **SAM ViT-L** (1.2GB) - High quality
  - **SAM ViT-H** (2.4GB) - Highest quality

  ## Output
  - `sam_model` - Loaded SAM model for use with SAMSegment node
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "SAMLoader"

  @impl true
  def label, do: "SAM Loader"

  @impl true
  def category, do: "Inference/Segmentation"

  @impl true
  def description do
    "Load a Segment Anything Model (SAM) for precise mask generation"
  end

  @impl true
  def input_spec do
    %{
      model_name: %{
        type: :enum,
        label: "MODEL",
        default: "mobile_sam",
        options: [
          %{value: "mobile_sam", label: "MobileSAM (40MB, Fast)"},
          %{value: "sam_vit_b", label: "SAM ViT-B (375MB, Better)"},
          %{value: "sam_vit_l", label: "SAM ViT-L (1.2GB, Great)"},
          %{value: "sam_vit_h", label: "SAM ViT-H (2.4GB, Best)"}
        ]
      }
    }
  end

  @impl true
  def output_spec do
    %{
      sam_model: %{type: :sam_model, label: "SAM_MODEL"}
    }
  end

  @impl true
  def process(inputs, config) do
    model_name = inputs["model_name"] || config["model_name"] || "mobile_sam"

    # Return a SAM model configuration (actual loading happens in SAMSegment)
    sam_model = %{
      "type" => "sam",
      "model_name" => model_name,
      "loaded" => true
    }

    {:ok, %{"sam_model" => sam_model}}
  end
end
