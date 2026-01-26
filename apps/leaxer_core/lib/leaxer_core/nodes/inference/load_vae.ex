defmodule LeaxerCore.Nodes.Inference.LoadVAE do
  @moduledoc """
  Load a VAE (Variational Autoencoder) model for use in the workflow.

  This node allows loading VAE models from the ~/models/vae/ directory
  with configurable tiling and CPU offload settings.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LoadVAE"

  @impl true
  def label, do: "Load VAE"

  @impl true
  def category, do: "Inference/Loaders"

  @impl true
  def description, do: "Load a VAE (Variational Autoencoder) model"

  @impl true
  def input_spec do
    %{
      vae_path: %{
        type: :vae_selector,
        label: "VAE MODEL",
        description: "Select a VAE model from the vae directory"
      },
      tiling: %{
        type: :boolean,
        label: "TILING",
        default: false,
        description: "Enable VAE tiling to reduce VRAM usage"
      },
      tile_size: %{
        type: :integer,
        label: "TILE SIZE",
        default: 512,
        min: 128,
        max: 2048,
        step: 64,
        description: "VAE tile size in pixels (128 to 2048)"
      },
      on_cpu: %{
        type: :boolean,
        label: "ON CPU",
        default: false,
        description: "Keep VAE on CPU to save VRAM"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      vae: %{type: :vae, label: "VAE"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LoadVAENode"}

  @impl true
  def process(inputs, config) do
    vae_path = inputs["vae_path"] || config["vae_path"]

    if is_nil(vae_path) or vae_path == "" do
      {:error, "No VAE model selected"}
    else
      case LeaxerCore.Models.Loader.load(vae_path) do
        {:ok, path} ->
          {status, format, description} = LeaxerCore.Models.Loader.detect_format(path)

          tiling = inputs["tiling"] || config["tiling"] || false
          tile_size = inputs["tile_size"] || config["tile_size"] || 512
          on_cpu = inputs["on_cpu"] || config["on_cpu"] || false

          # Validate tile_size range
          tile_size = max(128, min(2048, tile_size))

          vae_info = %{
            path: path,
            format: format,
            status: status,
            description: description,
            tiling: tiling,
            tile_size: tile_size,
            on_cpu: on_cpu,
            type: :vae
          }

          {:ok, %{"vae" => vae_info}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
