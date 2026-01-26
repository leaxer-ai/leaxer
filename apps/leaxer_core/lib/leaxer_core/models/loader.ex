defmodule LeaxerCore.Models.Loader do
  @moduledoc """
  Smart model loading - detects format, validates, and manages model paths.

  stable-diffusion.cpp natively supports .safetensors - users can drag-drop
  Civitai models directly without conversion. GGUF is optional for RAM/speed.

  ## Supported Formats

  - `.safetensors` - Native support, no conversion needed
  - `.ckpt` - Legacy format, native support
  - `.gguf` - Quantized format for reduced RAM/faster loading
  """

  require Logger

  @supported_formats ~w(.safetensors .ckpt .gguf)

  @doc """
  Load a model by path. Returns the path if valid, error otherwise.
  """
  def load(path) do
    ext = Path.extname(path) |> String.downcase()

    cond do
      not File.exists?(path) ->
        {:error, "File not found: #{path}"}

      ext not in @supported_formats ->
        {:error, "Unsupported format: #{ext}. Supported: #{Enum.join(@supported_formats, ", ")}"}

      true ->
        {:ok, path}
    end
  end

  @doc """
  Detect model format and return info about it.

  Returns `{status, format, description}` where status is:
  - `:native` - Can be used directly
  - `:quantized` - Optimized GGUF format
  - `:unknown` - Unsupported format
  """
  def detect_format(path) do
    ext = Path.extname(path) |> String.downcase()

    case ext do
      ".safetensors" -> {:native, :safetensors, "Ready to use"}
      ".ckpt" -> {:native, :ckpt, "Ready to use (legacy format)"}
      ".gguf" -> {:quantized, :gguf, "Quantized for speed/RAM"}
      _ -> {:unknown, nil, "Unsupported format"}
    end
  end

  @doc """
  List all models in the models directory.

  Returns a list of model info maps:
  ```
  [
    %{
      name: "dreamshaper-v8",
      path: "/path/to/dreamshaper-v8.safetensors",
      format: :safetensors,
      size_bytes: 2_000_000_000,
      type: :checkpoint
    }
  ]
  ```
  """
  def list_models(opts \\ []) do
    models_dir = Keyword.get(opts, :dir, LeaxerCore.Paths.models_dir())
    type_filter = Keyword.get(opts, :type)

    if File.dir?(models_dir) do
      models_dir
      |> scan_directory()
      |> Enum.filter(fn model ->
        is_nil(type_filter) or model.type == type_filter
      end)
      |> Enum.sort_by(& &1.name)
    else
      []
    end
  end

  @doc """
  List checkpoint models (main SD models).
  """
  def list_checkpoints do
    checkpoint_dir = Path.join(LeaxerCore.Paths.models_dir(), "checkpoint")
    list_models(dir: checkpoint_dir, type: :checkpoint)
  end

  @doc """
  List LoRA models.
  """
  def list_loras do
    lora_dir = Path.join(LeaxerCore.Paths.models_dir(), "lora")
    list_models(dir: lora_dir, type: :lora)
  end

  @doc """
  List VAE models.
  """
  def list_vaes do
    vae_dir = Path.join(LeaxerCore.Paths.models_dir(), "vae")
    list_models(dir: vae_dir, type: :vae)
  end

  @doc """
  List ControlNet models.
  """
  def list_controlnets do
    controlnet_dir = Path.join(LeaxerCore.Paths.models_dir(), "controlnet")
    list_models(dir: controlnet_dir, type: :controlnet)
  end

  @doc """
  List LLM models.
  """
  def list_llms do
    llm_dir = Path.join(LeaxerCore.Paths.models_dir(), "llm")
    list_models(dir: llm_dir, type: :llm)
  end

  @doc """
  Get model info by name or path.
  """
  def get_model(name_or_path) do
    cond do
      # Full path provided
      File.exists?(name_or_path) ->
        {:ok, build_model_info(name_or_path)}

      # Search by name in models directory
      true ->
        case find_model_by_name(name_or_path) do
          nil -> {:error, "Model not found: #{name_or_path}"}
          path -> {:ok, build_model_info(path)}
        end
    end
  end

  @doc """
  Get file size in human-readable format.
  """
  def format_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 1)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  # Private Functions

  defp scan_directory(dir) do
    patterns = Enum.map(@supported_formats, &"**/*#{&1}")

    patterns
    |> Enum.flat_map(fn pattern ->
      Path.join(dir, pattern)
      |> Path.wildcard()
    end)
    |> Enum.map(&build_model_info/1)
  end

  defp build_model_info(path) do
    stat = File.stat!(path)
    ext = Path.extname(path) |> String.downcase()
    basename = Path.basename(path, ext)
    {_, format, _} = detect_format(path)

    model_info = %{
      name: basename,
      path: path,
      format: format,
      size_bytes: stat.size,
      size_human: format_size(stat.size),
      type: infer_model_type(path),
      modified_at: stat.mtime
    }

    # Add quantization level for LLM models
    if infer_model_type(path) == :llm do
      Map.put(model_info, :quantization, parse_quantization_level(basename))
    else
      model_info
    end
  end

  defp infer_model_type(path) do
    path_lower = String.downcase(path)

    cond do
      String.contains?(path_lower, "/checkpoint/") -> :checkpoint
      String.contains?(path_lower, "/lora/") -> :lora
      String.contains?(path_lower, "/vae/") -> :vae
      String.contains?(path_lower, "/controlnet/") -> :controlnet
      String.contains?(path_lower, "/llm/") -> :llm
      String.contains?(path_lower, "/embeddings/") -> :embedding
      String.contains?(path_lower, "/text_encoder/") -> :text_encoder
      String.contains?(path_lower, "/upscaler/") -> :upscaler
      true -> :checkpoint
    end
  end

  defp find_model_by_name(name) do
    models_dir = LeaxerCore.Paths.models_dir()

    @supported_formats
    |> Enum.find_value(fn ext ->
      # Try exact match
      exact = Path.join(models_dir, "#{name}#{ext}")
      if File.exists?(exact), do: exact
    end)
    |> case do
      nil ->
        # Try fuzzy match
        list_models()
        |> Enum.find_value(fn model ->
          if String.contains?(String.downcase(model.name), String.downcase(name)) do
            model.path
          end
        end)

      path ->
        path
    end
  end

  defp parse_quantization_level(filename) do
    # Parse common GGUF quantization patterns like Q4_K_M, Q5_0, Q8_0, etc.
    case Regex.run(~r/[._-](Q\d+(?:_[KO])?(?:_[MSL])?)[._-]?/i, filename, capture: :all_but_first) do
      [quant] -> String.upcase(quant)
      nil -> "Unknown"
    end
  end
end
