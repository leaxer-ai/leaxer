defmodule LeaxerCore.Nodes.Inference.CacheSettings do
  @moduledoc """
  Configure caching settings for stable-diffusion.cpp.

  Supports multiple caching modes for faster inference:
  - ucache: Basic uniform caching
  - easycache: Easy cache mode with presets
  - dbcache: Database-style caching
  - taylorseer: Taylor series prediction

  Each mode can be combined with presets for easy configuration.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "CacheSettings"

  @impl true
  def label, do: "Cache Settings"

  @impl true
  def category, do: "Inference/Settings"

  @impl true
  def description, do: "Configure caching for faster inference"

  @impl true
  def input_spec do
    %{
      mode: %{
        type: :enum,
        label: "CACHE MODE",
        default: "none",
        options: [
          %{value: "none", label: "None (disabled)"},
          %{value: "ucache", label: "Uniform Cache"},
          %{value: "easycache", label: "Easy Cache"},
          %{value: "dbcache", label: "DB Cache"},
          %{value: "taylorseer", label: "Taylor Seer"}
        ],
        description: "Caching algorithm to use"
      },
      preset: %{
        type: :enum,
        label: "PRESET",
        default: "medium",
        options: [
          %{value: "slow", label: "Slow (highest quality)"},
          %{value: "medium", label: "Medium (balanced)"},
          %{value: "fast", label: "Fast (lower quality)"},
          %{value: "ultra", label: "Ultra (fastest)"}
        ],
        description: "Speed/quality tradeoff preset"
      },
      threshold: %{
        type: :float,
        label: "THRESHOLD",
        default: 0.5,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        optional: true,
        description: "Cache activation threshold"
      },
      warmup: %{
        type: :integer,
        label: "WARMUP",
        default: 2,
        min: 0,
        max: 20,
        step: 1,
        optional: true,
        description: "Warmup steps before caching"
      },
      start_step: %{
        type: :integer,
        label: "START STEP",
        default: 0,
        min: 0,
        max: 100,
        step: 1,
        optional: true,
        description: "Step to start caching"
      },
      end_step: %{
        type: :integer,
        label: "END STEP",
        default: -1,
        min: -1,
        max: 100,
        step: 1,
        optional: true,
        description: "Step to end caching (-1 = until end)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      cache_settings: %{type: :cache_settings, label: "CACHE SETTINGS"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "CacheSettingsNode"}

  @impl true
  def process(inputs, config) do
    mode = inputs["mode"] || config["mode"] || "none"

    settings = %{
      type: :cache_settings,
      mode: mode,
      preset: inputs["preset"] || config["preset"] || "medium",
      threshold: inputs["threshold"] || config["threshold"] || 0.5,
      warmup: inputs["warmup"] || config["warmup"] || 2,
      start_step: inputs["start_step"] || config["start_step"] || 0,
      end_step: inputs["end_step"] || config["end_step"] || -1
    }

    {:ok, %{"cache_settings" => settings}}
  end
end
