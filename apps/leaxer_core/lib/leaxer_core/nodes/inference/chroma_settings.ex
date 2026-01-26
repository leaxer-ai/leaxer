defmodule LeaxerCore.Nodes.Inference.ChromaSettings do
  @moduledoc """
  Configure Chroma model settings for stable-diffusion.cpp.

  Chroma models (including Chroma1-Radiance) support special mask settings:
  - disable_dit_mask: Disable DiT mask (improves some generations)
  - enable_t5_mask: Enable T5 text encoder mask
  - t5_mask_pad: T5 mask padding value

  Connect this node to GenerateImage to pass Chroma-specific settings.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "ChromaSettings"

  @impl true
  def label, do: "Chroma Settings"

  @impl true
  def category, do: "Inference/Settings"

  @impl true
  def description, do: "Configure settings for Chroma models"

  @impl true
  def input_spec do
    %{
      disable_dit_mask: %{
        type: :boolean,
        label: "DISABLE DIT MASK",
        default: false,
        description: "Disable DiT mask for generation"
      },
      enable_t5_mask: %{
        type: :boolean,
        label: "ENABLE T5 MASK",
        default: false,
        description: "Enable T5 text encoder mask"
      },
      t5_mask_pad: %{
        type: :integer,
        label: "T5 MASK PAD",
        default: 0,
        min: 0,
        max: 256,
        step: 1,
        description: "T5 mask padding value"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      chroma_settings: %{type: :chroma_settings, label: "CHROMA SETTINGS"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "ChromaSettingsNode"}

  @impl true
  def process(inputs, config) do
    settings = %{
      type: :chroma_settings,
      disable_dit_mask: inputs["disable_dit_mask"] || config["disable_dit_mask"] || false,
      enable_t5_mask: inputs["enable_t5_mask"] || config["enable_t5_mask"] || false,
      t5_mask_pad: inputs["t5_mask_pad"] || config["t5_mask_pad"] || 0
    }

    {:ok, %{"chroma_settings" => settings}}
  end
end
