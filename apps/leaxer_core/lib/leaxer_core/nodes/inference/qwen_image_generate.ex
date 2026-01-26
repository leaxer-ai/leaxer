defmodule LeaxerCore.Nodes.Inference.QwenImageGenerate do
  @moduledoc """
  Generate images using Qwen2.5-VL models via stable-diffusion.cpp.

  Qwen-Image models (OmniGen-1, Qwen-Turbo) use:
  - Separate diffusion model (--diffusion-model)
  - FLUX schnell VAE (--vae)
  - Qwen2.5-VL LLM encoder (--llm)
  - Flash attention for diffusion (--diffusion-fa)
  - Flow shift parameter (--flow-shift)

  Returns base64 output.

  Low VRAM requirements (~8GB for OmniGen-1).
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "QwenImageGenerate"

  @impl true
  def label, do: "Qwen Image Generate"

  @impl true
  def category, do: "Inference/Generate"

  @impl true
  def description, do: "Generate images using Qwen2.5-VL with diffusion models"

  @impl true
  def input_spec do
    %{
      diffusion_model: %{
        type: :string,
        label: "DIFFUSION MODEL",
        default: "",
        description: "Path to diffusion model (e.g., OmniGen-1, Qwen-Turbo)"
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
        description: "Path to Qwen2.5-VL LLM encoder (GGUF)"
      },
      prompt: %{type: :string, label: "PROMPT", default: "", multiline: true},
      negative_prompt: %{type: :string, label: "NEGATIVE PROMPT", default: "", multiline: true},
      steps: %{type: :integer, label: "STEPS", default: 20, min: 1, max: 100, step: 1},
      cfg_scale: %{type: :float, label: "CFG SCALE", default: 5.0, min: 1.0, max: 15.0, step: 0.5},
      width: %{type: :integer, label: "WIDTH", default: 1024, min: 64, max: 2048, step: 64},
      height: %{type: :integer, label: "HEIGHT", default: 1024, min: 64, max: 2048, step: 64},
      seed: %{type: :bigint, label: "SEED", default: -1},
      flow_shift: %{
        type: :float,
        label: "FLOW SHIFT",
        default: 3.0,
        min: 0.0,
        max: 10.0,
        step: 0.1,
        description: "Flow shift parameter for diffusion"
      },
      diffusion_fa: %{
        type: :boolean,
        label: "FLASH ATTENTION",
        default: true,
        description: "Enable flash attention for diffusion model"
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
  def ui_component, do: {:custom, "QwenImageGenerateNode"}

  @impl true
  def process(inputs, config) do
    diffusion_model = inputs["diffusion_model"] || config["diffusion_model"]
    vae = inputs["vae"] || config["vae"]
    llm = inputs["llm"] || config["llm"]
    prompt = inputs["prompt"] || config["prompt"] || ""

    cond do
      is_nil(diffusion_model) or diffusion_model == "" ->
        {:error, "Diffusion model is required"}

      is_nil(vae) or vae == "" ->
        {:error, "VAE model is required (use FLUX schnell VAE)"}

      is_nil(llm) or llm == "" ->
        {:error, "LLM encoder is required (Qwen2.5-VL GGUF)"}

      prompt == "" ->
        {:error, "Prompt is required"}

      true ->
        opts = [
          # Qwen-Image uses diffusion_model instead of main model
          model: diffusion_model,
          diffusion_model: diffusion_model,
          vae: vae,
          llm: llm,
          negative_prompt: inputs["negative_prompt"] || config["negative_prompt"] || "",
          steps: inputs["steps"] || config["steps"] || 20,
          cfg_scale: inputs["cfg_scale"] || config["cfg_scale"] || 5.0,
          width: inputs["width"] || config["width"] || 1024,
          height: inputs["height"] || config["height"] || 1024,
          seed: inputs["seed"] || config["seed"] || -1,
          sampler: "euler",
          flow_shift: inputs["flow_shift"] || config["flow_shift"] || 3.0,
          diffusion_fa: inputs["diffusion_fa"] || config["diffusion_fa"] || true,
          compute_backend: config["compute_backend"] || "cpu",
          node_id: config["node_id"],
          job_id: config["job_id"]
        ]

        case LeaxerCore.Workers.StableDiffusion.generate(prompt, opts) do
          {:ok, %{path: path}} ->
            # Read result as base64
            case File.read(path) do
              {:ok, binary} ->
                {:ok,
                 %{
                   "image" => %{data: Base.encode64(binary), mime_type: "image/png", type: :image}
                 }}

              {:error, _} ->
                {:ok, %{"image" => %{path: path, type: :image}}}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
