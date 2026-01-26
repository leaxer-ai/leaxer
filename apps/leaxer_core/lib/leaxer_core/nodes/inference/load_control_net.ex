defmodule LeaxerCore.Nodes.Inference.LoadControlNet do
  @moduledoc """
  Load a ControlNet model for use in the workflow.

  This node allows loading ControlNet models from the ~/models/controlnet/ directory
  with configurable strength and CPU offload settings.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LoadControlNet"

  @impl true
  def label, do: "Load ControlNet"

  @impl true
  def category, do: "Inference/Loaders"

  @impl true
  def description, do: "Load a ControlNet model for guided image generation"

  @impl true
  def input_spec do
    %{
      controlnet_path: %{
        type: :controlnet_selector,
        label: "CONTROLNET MODEL",
        description: "Select a ControlNet model from the controlnet directory"
      },
      strength: %{
        type: :float,
        label: "STRENGTH",
        default: 1.0,
        min: 0.0,
        max: 1.0,
        step: 0.1,
        description: "ControlNet influence strength (0.0 to 1.0)"
      },
      keep_on_cpu: %{
        type: :boolean,
        label: "KEEP ON CPU",
        default: false,
        description: "Keep ControlNet model on CPU to save VRAM"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      controlnet: %{type: :controlnet, label: "CONTROLNET"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LoadControlNetNode"}

  @impl true
  def process(inputs, config) do
    controlnet_path = inputs["controlnet_path"] || config["controlnet_path"]

    if is_nil(controlnet_path) or controlnet_path == "" do
      {:error, "No ControlNet model selected"}
    else
      case LeaxerCore.Models.Loader.load(controlnet_path) do
        {:ok, path} ->
          {status, format, description} = LeaxerCore.Models.Loader.detect_format(path)

          strength = inputs["strength"] || config["strength"] || 1.0
          keep_on_cpu = inputs["keep_on_cpu"] || config["keep_on_cpu"] || false

          # Validate strength range
          strength = max(0.0, min(1.0, strength))

          controlnet_info = %{
            path: path,
            format: format,
            status: status,
            description: description,
            strength: strength,
            keep_on_cpu: keep_on_cpu,
            type: :controlnet
          }

          {:ok, %{"controlnet" => controlnet_info}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
