defmodule LeaxerCore.Nodes.Inference.LoadTextEncoders do
  @moduledoc """
  Load text encoders for FLUX.1, SD3.5, and other models requiring external encoders.

  This node allows configuring CLIP L, CLIP G, and T5-XXL text encoders,
  which are required for models like FLUX.1-dev, FLUX.1-schnell, and SD3.5.

  ## Supported Encoders
  - CLIP L (clip_l): Required for FLUX.1 and SD3.5
  - CLIP G (clip_g): Required for SD3.5
  - T5-XXL (t5xxl): Required for FLUX.1 and SD3.5

  ## Memory Optimization
  Enable `clip_on_cpu` to offload CLIP encoders to CPU, reducing VRAM usage.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LoadTextEncoders"

  @impl true
  def label, do: "Load Text Encoders"

  @impl true
  def category, do: "Inference/Loaders"

  @impl true
  def description, do: "Load CLIP and T5 text encoders for FLUX.1/SD3.5 models"

  @impl true
  def input_spec do
    %{
      clip_l: %{
        type: :string,
        label: "CLIP L",
        default: "",
        optional: true,
        description: "Path to CLIP L encoder (required for FLUX.1, SD3.5)"
      },
      clip_g: %{
        type: :string,
        label: "CLIP G",
        default: "",
        optional: true,
        description: "Path to CLIP G encoder (required for SD3.5)"
      },
      t5xxl: %{
        type: :string,
        label: "T5-XXL",
        default: "",
        optional: true,
        description: "Path to T5-XXL encoder (required for FLUX.1, SD3.5)"
      },
      clip_on_cpu: %{
        type: :boolean,
        label: "CLIP ON CPU",
        default: false,
        description: "Offload CLIP encoders to CPU to save VRAM"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      text_encoders: %{type: :text_encoders, label: "TEXT ENCODERS"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LoadTextEncodersNode"}

  @impl true
  def process(inputs, config) do
    clip_l = inputs["clip_l"] || config["clip_l"]
    clip_g = inputs["clip_g"] || config["clip_g"]
    t5xxl = inputs["t5xxl"] || config["t5xxl"]
    clip_on_cpu = inputs["clip_on_cpu"] || config["clip_on_cpu"] || false

    # Validate at least one encoder is provided
    has_any =
      (is_binary(clip_l) and clip_l != "") or
        (is_binary(clip_g) and clip_g != "") or
        (is_binary(t5xxl) and t5xxl != "")

    if not has_any do
      {:error, "At least one text encoder path must be provided"}
    else
      # Validate paths exist (if provided)
      errors =
        []
        |> validate_path(clip_l, "CLIP L")
        |> validate_path(clip_g, "CLIP G")
        |> validate_path(t5xxl, "T5-XXL")

      if length(errors) > 0 do
        {:error, Enum.join(errors, "; ")}
      else
        text_encoders = %{
          clip_l: normalize_path(clip_l),
          clip_g: normalize_path(clip_g),
          t5xxl: normalize_path(t5xxl),
          clip_on_cpu: clip_on_cpu,
          type: :text_encoders
        }

        {:ok, %{"text_encoders" => text_encoders}}
      end
    end
  end

  # Private helpers

  defp validate_path(errors, nil, _name), do: errors
  defp validate_path(errors, "", _name), do: errors

  defp validate_path(errors, path, name) when is_binary(path) do
    if File.exists?(path) do
      errors
    else
      ["#{name} not found: #{path}" | errors]
    end
  end

  defp validate_path(errors, _, _), do: errors

  defp normalize_path(nil), do: nil
  defp normalize_path(""), do: nil
  defp normalize_path(path), do: path
end
