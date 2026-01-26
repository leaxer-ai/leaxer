defmodule LeaxerCore.Nodes.Inference.QwenImageEdit do
  @moduledoc """
  Edit images using Qwen-Image 2509/2511 variants via stable-diffusion.cpp.

  Supports two editing modes:
  - Qwen-Image 2509: Uses --llm_vision for vision-language editing
  - Qwen-Image 2511: Uses --qwen-image-zero-cond-t for zero-conditioned editing

  Accepts both base64 and path-based image inputs, returns base64 output.

  Both use a source image (-r) and an edit prompt to guide the transformation.
  """

  use LeaxerCore.Nodes.Behaviour

  alias LeaxerCore.Vips

  @impl true
  def type, do: "QwenImageEdit"

  @impl true
  def label, do: "Qwen Image Edit"

  @impl true
  def category, do: "Inference/Generate"

  @impl true
  def description, do: "Edit images using Qwen-Image 2509/2511 variants"

  @impl true
  def input_spec do
    %{
      source_image: %{
        type: :image,
        label: "SOURCE IMAGE",
        description: "Image to edit"
      },
      diffusion_model: %{
        type: :string,
        label: "DIFFUSION MODEL",
        default: "",
        description: "Path to Qwen-Image diffusion model"
      },
      vae: %{
        type: :string,
        label: "VAE",
        default: "",
        description: "Path to VAE model (use FLUX schnell VAE)"
      },
      llm: %{
        type: :string,
        label: "LLM",
        default: "",
        description: "Path to LLM encoder (GGUF)"
      },
      llm_vision: %{
        type: :string,
        label: "LLM VISION",
        default: "",
        optional: true,
        description: "Path to vision LLM (for 2509 variant)"
      },
      edit_prompt: %{
        type: :string,
        label: "EDIT PROMPT",
        default: "",
        multiline: true,
        description: "Describe the edit to perform"
      },
      variant: %{
        type: :enum,
        label: "VARIANT",
        default: "2509",
        options: [
          %{value: "2509", label: "Qwen-Image 2509 (Vision)"},
          %{value: "2511", label: "Qwen-Image 2511 (Zero-Cond)"}
        ],
        description: "Model variant for editing mode"
      },
      steps: %{type: :integer, label: "STEPS", default: 20, min: 1, max: 100, step: 1},
      cfg_scale: %{type: :float, label: "CFG SCALE", default: 5.0, min: 1.0, max: 15.0, step: 0.5},
      seed: %{type: :bigint, label: "SEED", default: -1},
      zero_cond_t: %{
        type: :float,
        label: "ZERO COND T",
        default: 0.5,
        min: 0.0,
        max: 1.0,
        step: 0.05,
        optional: true,
        description: "Zero conditioning threshold (for 2511 variant)"
      },
      flow_shift: %{
        type: :float,
        label: "FLOW SHIFT",
        default: 3.0,
        min: 0.0,
        max: 10.0,
        step: 0.1,
        description: "Flow shift parameter"
      },
      diffusion_fa: %{
        type: :boolean,
        label: "FLASH ATTENTION",
        default: true,
        description: "Enable flash attention"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{type: :image, label: "IMAGE"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "QwenImageEditNode"}

  @impl true
  def process(inputs, config) do
    source_image = inputs["source_image"]
    diffusion_model = inputs["diffusion_model"] || config["diffusion_model"]
    vae = inputs["vae"] || config["vae"]
    llm = inputs["llm"] || config["llm"]
    edit_prompt = inputs["edit_prompt"] || config["edit_prompt"] || ""
    variant = inputs["variant"] || config["variant"] || "2509"

    cond do
      is_nil(source_image) ->
        {:error, "Source image is required"}

      is_nil(diffusion_model) or diffusion_model == "" ->
        {:error, "Diffusion model is required"}

      is_nil(vae) or vae == "" ->
        {:error, "VAE model is required"}

      is_nil(llm) or llm == "" ->
        {:error, "LLM encoder is required"}

      edit_prompt == "" ->
        {:error, "Edit prompt is required"}

      true ->
        # Materialize source image to temp file if base64
        case materialize_image(source_image) do
          {:ok, source_path, temp_file} ->
            # Build base options
            opts = [
              model: diffusion_model,
              diffusion_model: diffusion_model,
              vae: vae,
              llm: llm,
              # Use -r for reference/source image in edit mode
              ref_image: source_path,
              steps: inputs["steps"] || config["steps"] || 20,
              cfg_scale: inputs["cfg_scale"] || config["cfg_scale"] || 5.0,
              seed: inputs["seed"] || config["seed"] || -1,
              sampler: "euler",
              flow_shift: inputs["flow_shift"] || config["flow_shift"] || 3.0,
              diffusion_fa: inputs["diffusion_fa"] || config["diffusion_fa"] || true,
              compute_backend: config["compute_backend"] || "cpu",
              node_id: config["node_id"],
              job_id: config["job_id"]
            ]

            # Add variant-specific options
            opts =
              case variant do
                "2509" ->
                  llm_vision = inputs["llm_vision"] || config["llm_vision"]

                  if llm_vision && llm_vision != "",
                    do: opts ++ [llm_vision: llm_vision],
                    else: opts

                "2511" ->
                  zero_cond_t = inputs["zero_cond_t"] || config["zero_cond_t"] || 0.5
                  opts ++ [qwen_image_zero_cond_t: zero_cond_t]

                _ ->
                  opts
              end

            result =
              case LeaxerCore.Workers.StableDiffusion.generate(edit_prompt, opts) do
                {:ok, %{path: path}} ->
                  # Read result as base64
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
            {:error, "Source image is required"}
        end
    end
  end

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
end
