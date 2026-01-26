defmodule LeaxerCore.Nodes.Inference.SamplerSettings do
  @moduledoc """
  Configure sampler settings for stable-diffusion.cpp.

  Supports various sampling methods and schedulers:
  - Methods: euler, euler_a, heun, dpm2, dpm++2s_a, dpm++2m, ipndm, lcm, ddim, tcd
  - Schedulers: discrete, karras, exponential, ays, gits

  Each combination can produce different quality/speed characteristics.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "SamplerSettings"

  @impl true
  def label, do: "Sampler Settings"

  @impl true
  def category, do: "Inference/Settings"

  @impl true
  def description, do: "Configure sampling method and scheduler"

  @impl true
  def input_spec do
    %{
      method: %{
        type: :enum,
        label: "SAMPLING METHOD",
        default: "euler_a",
        options: [
          %{value: "euler", label: "Euler"},
          %{value: "euler_a", label: "Euler Ancestral"},
          %{value: "heun", label: "Heun"},
          %{value: "dpm2", label: "DPM2"},
          %{value: "dpm++2s_a", label: "DPM++ 2S Ancestral"},
          %{value: "dpm++2m", label: "DPM++ 2M"},
          %{value: "ipndm", label: "iPNDM"},
          %{value: "lcm", label: "LCM"},
          %{value: "ddim", label: "DDIM"},
          %{value: "tcd", label: "TCD"}
        ],
        description: "Sampling algorithm to use"
      },
      scheduler: %{
        type: :enum,
        label: "SCHEDULER",
        default: "discrete",
        options: [
          %{value: "discrete", label: "Discrete"},
          %{value: "karras", label: "Karras"},
          %{value: "exponential", label: "Exponential"},
          %{value: "ays", label: "AYS"},
          %{value: "gits", label: "GITS"}
        ],
        description: "Noise schedule type"
      },
      eta: %{
        type: :float,
        label: "ETA",
        default: 0.0,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        optional: true,
        description: "Eta for DDIM/ancestral samplers (0 = deterministic)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      sampler_settings: %{type: :sampler_settings, label: "SAMPLER SETTINGS"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "SamplerSettingsNode"}

  @impl true
  def process(inputs, config) do
    settings = %{
      type: :sampler_settings,
      method: inputs["method"] || config["method"] || "euler_a",
      scheduler: inputs["scheduler"] || config["scheduler"] || "discrete",
      eta: inputs["eta"] || config["eta"] || 0.0
    }

    {:ok, %{"sampler_settings" => settings}}
  end
end
