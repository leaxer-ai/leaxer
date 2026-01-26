defmodule LeaxerCore.Nodes.Inference.LoadLoRA do
  @moduledoc """
  Load a LoRA (Low-Rank Adaptation) model for use in the workflow.

  This node allows loading LoRA models from the ~/models/lora/ directory
  with configurable multiplier and apply mode settings.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LoadLoRA"

  @impl true
  def label, do: "Load LoRA"

  @impl true
  def category, do: "Inference/Loaders"

  @impl true
  def description, do: "Load a LoRA (Low-Rank Adaptation) model"

  @impl true
  def input_spec do
    %{
      lora_path: %{
        type: :lora_selector,
        label: "LoRA MODEL",
        description: "Select a LoRA model from the lora directory"
      },
      multiplier: %{
        type: :float,
        label: "MULTIPLIER",
        default: 1.0,
        min: 0.0,
        max: 2.0,
        step: 0.1,
        description: "LoRA strength multiplier (0.0 to 2.0)"
      },
      apply_mode: %{
        type: :enum,
        label: "APPLY MODE",
        default: "auto",
        options: [
          %{value: "auto", label: "Auto"},
          %{value: "immediately", label: "Immediately"},
          %{value: "at_runtime", label: "At Runtime"}
        ],
        description: "When to apply the LoRA model"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      lora: %{type: :lora, label: "LoRA"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LoadLoRANode"}

  @impl true
  def process(inputs, config) do
    lora_path = inputs["lora_path"] || config["lora_path"]

    if is_nil(lora_path) or lora_path == "" do
      {:error, "No LoRA model selected"}
    else
      case LeaxerCore.Models.Loader.load(lora_path) do
        {:ok, path} ->
          {status, format, description} = LeaxerCore.Models.Loader.detect_format(path)

          multiplier = inputs["multiplier"] || config["multiplier"] || 1.0
          apply_mode = inputs["apply_mode"] || config["apply_mode"] || "auto"

          # Validate multiplier range
          multiplier = max(0.0, min(2.0, multiplier))

          # Validate apply_mode
          apply_mode =
            if apply_mode in ["auto", "immediately", "at_runtime"] do
              apply_mode
            else
              "auto"
            end

          lora_info = %{
            path: path,
            format: format,
            status: status,
            description: description,
            multiplier: multiplier,
            apply_mode: apply_mode,
            type: :lora
          }

          {:ok, %{"lora" => lora_info}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
