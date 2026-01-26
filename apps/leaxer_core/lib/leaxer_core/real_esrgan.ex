defmodule LeaxerCore.RealESRGAN do
  @moduledoc """
  Wrapper for Real-ESRGAN-ncnn-vulkan command-line operations.
  Provides interface for AI-powered image upscaling.
  """

  alias LeaxerCore.BinaryFinder

  require Logger

  @doc """
  Get the path to the Real-ESRGAN binary.
  """
  def bin_path do
    BinaryFinder.priv_bin_path("realesrgan-ncnn-vulkan")
  end

  @doc """
  Get the path to the Real-ESRGAN models directory.
  """
  def models_path do
    path = Path.join([Application.app_dir(:leaxer_core, "priv"), "models", "realesrgan"])
    # Convert to native path separators for Windows compatibility
    case :os.type() do
      {:win32, _} -> String.replace(path, "/", "\\")
      _ -> path
    end
  end

  @doc """
  Check if Real-ESRGAN is installed and available.
  Returns {:ok, binary_path} if available, {:error, reason} otherwise.
  """
  def check_installation do
    path = bin_path()

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "Real-ESRGAN binary not found at #{path}"}
    end
  end

  @doc """
  Get available models with their descriptions.
  """
  def available_models do
    %{
      "realesrgan-x4plus" => %{
        label: "Real-ESRGAN 4x Plus",
        scale: 4,
        description: "Best quality 4x upscale"
      },
      "realesrgan-x4plus-anime" => %{
        label: "Real-ESRGAN 4x Plus (Anime/Art)",
        scale: 4,
        description: "Optimized for artwork"
      },
      "realesr-animevideov3-x2" => %{
        label: "Real-ESRGAN 2x",
        scale: 2,
        description: "Fast 2x upscale"
      },
      "realesr-animevideov3-x3" => %{
        label: "Real-ESRGAN 3x",
        scale: 3,
        description: "Fast 3x upscale"
      },
      "realesr-animevideov3-x4" => %{
        label: "Real-ESRGAN 4x",
        scale: 4,
        description: "Fast 4x upscale"
      }
    }
  end

  @doc """
  Get the scale factor for a given model.
  Each model has a fixed scale - using wrong scale corrupts output.
  """
  def get_model_scale(model_name) do
    case available_models()[model_name] do
      %{scale: scale} -> scale
      # Default to 4x for unknown models
      _ -> 4
    end
  end

  @doc """
  Upscale an image using Real-ESRGAN.

  ## Options
  - `:model` - Model name (default: "realesrgan-x4plus")
  - `:scale` - Output scale (default: 4, can be 2, 3, or 4 depending on model)
  - `:tile_size` - Tile size for processing (default: 0 = auto)
  - `:gpu_id` - GPU device ID (default: 0)

  ## Examples

      iex> upscale("input.jpg", "output.png", model: "realesrgan-x4plus")
      {:ok, "output.png"}
  """
  def upscale(input_path, output_path, opts \\ []) do
    with {:ok, _} <- check_installation(),
         :ok <- validate_input(input_path),
         :ok <- validate_model(opts[:model] || "realesrgan-x4plus") do
      do_upscale(input_path, output_path, opts)
    end
  end

  defp validate_input(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "Input file not found: #{path}"}
    end
  end

  defp validate_model(model_name) do
    models = available_models()

    if Map.has_key?(models, model_name) do
      :ok
    else
      {:error, "Unknown model: #{model_name}. Available: #{Map.keys(models) |> Enum.join(", ")}"}
    end
  end

  defp do_upscale(input_path, output_path, opts) do
    model = opts[:model] || "realesrgan-x4plus"
    # Always use model's native scale to prevent corruption
    scale = get_model_scale(model)
    gpu_id = opts[:gpu_id] || 0

    # Ensure output directory exists
    output_dir = Path.dirname(output_path)
    File.mkdir_p!(output_dir)

    # Get binary path
    binary_path = bin_path()
    model_dir = models_path()

    # Build command arguments (no tile_size = let Real-ESRGAN auto-detect)
    args = [
      "-i",
      input_path,
      "-o",
      output_path,
      "-n",
      model,
      "-s",
      to_string(scale),
      "-g",
      to_string(gpu_id),
      "-m",
      model_dir,
      # Always output PNG for quality
      "-f",
      "png"
    ]

    Logger.info("Running Real-ESRGAN: #{binary_path} #{Enum.join(args, " ")}")

    case System.cmd(binary_path, args,
           stderr_to_stdout: true,
           env: [{"DYLD_LIBRARY_PATH", Path.dirname(binary_path)}]
         ) do
      {output, 0} ->
        Logger.info("Real-ESRGAN completed: #{output}")
        {:ok, output_path}

      {error, code} ->
        Logger.error("Real-ESRGAN failed (exit #{code}): #{error}")
        {:error, "Real-ESRGAN operation failed: #{error}"}
    end
  rescue
    e ->
      Logger.error("Real-ESRGAN exception: #{inspect(e)}")
      {:error, "Real-ESRGAN error: #{Exception.message(e)}"}
  end
end
