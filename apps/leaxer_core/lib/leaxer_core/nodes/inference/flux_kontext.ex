defmodule LeaxerCore.Nodes.Inference.FluxKontext do
  @moduledoc """
  FLUX.1-Kontext-dev image editing and inpainting node.

  FLUX.1-Kontext is a specialized model for context-aware image editing,
  enabling reference-based editing and inpainting with high fidelity.

  Accepts both base64 and path-based image inputs, returns base64 output.

  ## Use Cases
  - Reference-based image editing
  - Context-aware inpainting
  - Style transfer with reference images
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Vips

  @impl true
  def type, do: "FluxKontext"

  @impl true
  def label, do: "FLUX Kontext"

  @impl true
  def category, do: "Inference/Generate"

  @impl true
  def description, do: "FLUX.1-Kontext image editing with reference image support"

  @impl true
  def input_spec do
    %{
      model: %{type: :model, label: "MODEL"},
      ref_image: %{
        type: :image,
        label: "REFERENCE IMAGE",
        description: "Reference image for context-aware editing"
      },
      prompt: %{type: :string, label: "PROMPT", default: "", multiline: true},
      negative_prompt: %{type: :string, label: "NEGATIVE PROMPT", default: "", multiline: true},
      cfg_scale: %{
        type: :float,
        label: "CFG SCALE",
        default: 1.0,
        min: 1.0,
        max: 10.0,
        step: 0.1
      },
      width: %{type: :integer, label: "WIDTH", default: 1024, min: 64, max: 2048, step: 64},
      height: %{type: :integer, label: "HEIGHT", default: 1024, min: 64, max: 2048, step: 64},
      steps: %{type: :integer, label: "STEPS", default: 20, min: 1, max: 100, step: 1},
      seed: %{type: :bigint, label: "SEED", default: -1},
      text_encoders: %{type: :text_encoders, label: "TEXT ENCODERS", optional: true}
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{type: :image, label: "IMAGE"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "FluxKontextNode"}

  @impl true
  def process(inputs, config) do
    model_path =
      case inputs["model"] do
        %{path: path} -> path
        path when is_binary(path) -> path
        _ -> config["model"]
      end

    if is_nil(model_path) or model_path == "" do
      {:error, "No model selected"}
    else
      # Reference image is required for Kontext
      ref_image = inputs["ref_image"]

      if is_nil(ref_image) do
        {:error, "Reference image is required for FLUX Kontext"}
      else
        # Materialize ref_image to temp file if base64
        case materialize_image(ref_image) do
          {:ok, ref_image_path, temp_file} ->
            prompt = inputs["prompt"] || config["prompt"] || ""

            # Process text encoders if provided
            text_encoder_opts = process_text_encoder_input(inputs["text_encoders"])

            # Get model caching strategy from system settings
            strategy = config["model_caching_strategy"] || "auto"

            # FLUX Kontext defaults: cfg_scale 1.0, euler sampler
            opts =
              [
                model: model_path,
                init_img: ref_image_path,
                negative_prompt: inputs["negative_prompt"] || config["negative_prompt"] || "",
                steps: inputs["steps"] || config["steps"] || 20,
                cfg_scale: inputs["cfg_scale"] || config["cfg_scale"] || 1.0,
                width: inputs["width"] || config["width"] || 1024,
                height: inputs["height"] || config["height"] || 1024,
                seed: inputs["seed"] || config["seed"] || -1,
                sampler: "euler",
                compute_backend: config["compute_backend"] || "cpu",
                node_id: config["node_id"],
                job_id: config["job_id"],
                stream_base64: true
              ] ++ text_encoder_opts

            # Select worker based on system caching strategy
            worker =
              case strategy do
                "server-mode" ->
                  LeaxerCore.Workers.StableDiffusionServer

                "cli-mode" ->
                  LeaxerCore.Workers.StableDiffusion

                _ ->
                  if LeaxerCore.Workers.StableDiffusionServer.available?() do
                    LeaxerCore.Workers.StableDiffusionServer
                  else
                    LeaxerCore.Workers.StableDiffusion
                  end
              end

            result =
              case worker.generate(prompt, opts) do
                {:ok, %{data: data, mime_type: mime_type}} ->
                  {:ok, %{"image" => %{data: data, mime_type: mime_type, type: :image}}}

                {:ok, %{path: path}} ->
                  # CLI mode returns file path - read as base64
                  case File.read(path) do
                    {:ok, binary} ->
                      {:ok,
                       %{
                         "image" => %{
                           data: Base.encode64(binary),
                           mime_type: "image/png",
                           type: :image
                         }
                       }}

                    {:error, _} ->
                      {:ok, %{"image" => %{path: path, type: :image}}}
                  end

                {:error, reason} ->
                  {:error, reason}
              end

            # Cleanup temp file
            if temp_file, do: File.rm(temp_file)

            result

          :error ->
            {:error, "Reference image is required for FLUX Kontext"}
        end
      end
    end
  end

  # Private helpers

  defp materialize_image(%{data: _, mime_type: _} = image) do
    case Vips.materialize_to_temp(image) do
      {:ok, path} -> {:ok, path, path}
      {:error, _} -> :error
    end
  end

  defp materialize_image(%{"data" => _, "mime_type" => _} = image) do
    case Vips.materialize_to_temp(image) do
      {:ok, path} -> {:ok, path, path}
      {:error, _} -> :error
    end
  end

  defp materialize_image(%{path: path}) when is_binary(path), do: {:ok, path, nil}
  defp materialize_image(%{"path" => path}) when is_binary(path), do: {:ok, path, nil}
  defp materialize_image(path) when is_binary(path), do: {:ok, path, nil}
  defp materialize_image(_), do: :error

  defp process_text_encoder_input(nil), do: []

  defp process_text_encoder_input(text_encoders) when is_map(text_encoders) do
    opts = []

    opts =
      case text_encoders[:clip_l] do
        nil -> opts
        "" -> opts
        path when is_binary(path) -> opts ++ [clip_l: path]
        _ -> opts
      end

    opts =
      case text_encoders[:clip_g] do
        nil -> opts
        "" -> opts
        path when is_binary(path) -> opts ++ [clip_g: path]
        _ -> opts
      end

    opts =
      case text_encoders[:t5xxl] do
        nil -> opts
        "" -> opts
        path when is_binary(path) -> opts ++ [t5xxl: path]
        _ -> opts
      end

    if text_encoders[:clip_on_cpu] do
      opts ++ [clip_on_cpu: true]
    else
      opts
    end
  end

  defp process_text_encoder_input(_), do: []
end
