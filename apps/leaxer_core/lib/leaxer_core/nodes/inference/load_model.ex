defmodule LeaxerCore.Nodes.Inference.LoadModel do
  @moduledoc """
  Load a Stable Diffusion model for use in the workflow.

  This node validates and prepares model files for inference.
  Supports .safetensors, .ckpt, and .gguf formats.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LoadModel"

  @impl true
  def label, do: "Load Checkpoint"

  @impl true
  def category, do: "Inference/Loaders"

  @impl true
  def description, do: "Load a Stable Diffusion checkpoint model"

  @impl true
  def input_spec do
    %{
      model_path: %{
        type: :model_selector,
        label: "MODEL",
        description: "Select a model from the models directory"
      },
      weight_type: %{
        type: :enum,
        label: "WEIGHT TYPE",
        default: "default",
        optional: true,
        options: [
          %{value: "default", label: "Default (auto)"},
          %{value: "f32", label: "Float32 (highest quality)"},
          %{value: "f16", label: "Float16 (good quality)"},
          %{value: "q8_0", label: "Q8_0 (8-bit quantized)"},
          %{value: "q5_1", label: "Q5_1 (5-bit quantized)"},
          %{value: "q5_0", label: "Q5_0 (5-bit quantized)"},
          %{value: "q4_1", label: "Q4_1 (4-bit quantized)"},
          %{value: "q4_0", label: "Q4_0 (4-bit quantized)"},
          %{value: "q4_k", label: "Q4_K (k-quant 4-bit)"},
          %{value: "q3_k", label: "Q3_K (k-quant 3-bit)"},
          %{value: "q2_k", label: "Q2_K (k-quant 2-bit)"}
        ],
        description: "Model weight quantization type (GGUF models)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      model: %{type: :model, label: "MODEL"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LoadModelNode"}

  @impl true
  def process(inputs, config) do
    model_path = inputs["model_path"] || config["model_path"]

    if is_nil(model_path) or model_path == "" do
      {:error, "No model selected"}
    else
      case LeaxerCore.Models.Loader.load(model_path) do
        {:ok, path} ->
          {status, format, description} = LeaxerCore.Models.Loader.detect_format(path)

          # Get weight type (only relevant for GGUF models)
          weight_type = inputs["weight_type"] || config["weight_type"] || "default"

          model_info = %{
            path: path,
            format: format,
            status: status,
            description: description,
            type: :model,
            weight_type: weight_type
          }

          {:ok, %{"model" => model_info}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
