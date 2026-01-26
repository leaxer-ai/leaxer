defmodule LeaxerCore.Nodes.LLM.LoadLLM do
  @moduledoc """
  Load a Large Language Model for use in text generation workflows.

  This node allows loading LLM models from the ~/models/llm/ directory
  with configurable context size and GPU layers settings.
  Validates that the model file exists and is in .gguf format.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "LoadLLM"

  @impl true
  def label, do: "Load LLM"

  @impl true
  def category, do: "Inference/LLM"

  @impl true
  def description, do: "Load a Large Language Model for text generation"

  @impl true
  def input_spec do
    %{
      model_path: %{
        type: :llm_selector,
        label: "LLM MODEL",
        description: "Select an LLM model from the llm directory (.gguf files)"
      },
      context_size: %{
        type: :integer,
        label: "CONTEXT SIZE",
        default: 4096,
        min: 512,
        max: 32768,
        step: 256,
        description: "Maximum context length in tokens (512 to 32768)"
      },
      gpu_layers: %{
        type: :integer,
        label: "GPU LAYERS",
        default: -1,
        min: -1,
        max: 100,
        step: 1,
        description: "Number of layers to offload to GPU (-1 for all)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      llm: %{type: :llm, label: "LLM"}
    }
  end

  @impl true
  def ui_component, do: {:custom, "LoadLLMNode"}

  @impl true
  def process(inputs, config) do
    model_path = inputs["model_path"] || config["model_path"]

    if is_nil(model_path) or model_path == "" do
      {:error, "No LLM model selected"}
    else
      case validate_gguf_model(model_path) do
        {:ok, path} ->
          {status, format, description} = LeaxerCore.Models.Loader.detect_format(path)

          context_size = inputs["context_size"] || config["context_size"] || 4096
          gpu_layers = inputs["gpu_layers"] || config["gpu_layers"] || -1

          # Validate context_size range
          context_size = max(512, min(32768, context_size))

          # Validate gpu_layers range
          gpu_layers = max(-1, min(100, gpu_layers))

          llm_info = %{
            path: path,
            format: format,
            status: status,
            description: description,
            context_size: context_size,
            gpu_layers: gpu_layers,
            type: :llm
          }

          {:ok, %{"llm" => llm_info}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private helper to validate LLM models (.gguf format)
  defp validate_gguf_model(path) do
    ext = Path.extname(path) |> String.downcase()

    cond do
      not File.exists?(path) ->
        {:error, "File not found: #{path}"}

      ext != ".gguf" ->
        {:error, "LLM models must be in .gguf format. Found: #{ext}"}

      true ->
        {:ok, path}
    end
  end
end
