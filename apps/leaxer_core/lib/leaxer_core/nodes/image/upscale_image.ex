defmodule LeaxerCore.Nodes.Image.UpscaleImage do
  @moduledoc """
  AI-powered image upscaling using Real-ESRGAN.

  Enhances image resolution using AI models trained for photo-realistic
  and anime/artwork upscaling. Includes multiple models optimized for
  different content types.

  Accepts both base64 and path-based inputs, returns base64 output.

  ## Examples

      iex> UpscaleImage.process(%{"image" => %{"data" => "...", "mime_type" => "image/png"}}, %{"model" => "realesrgan-x4plus"})
      {:ok, %{"image" => %{"data" => "...", "mime_type" => "image/png", "width" => 4096, "height" => 4096}}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.RealESRGAN
  alias LeaxerCore.Vips

  @impl true
  def type, do: "UpscaleImage"

  @impl true
  def label, do: "Upscale Image (AI)"

  @impl true
  def category, do: "Image/Upscale"

  @impl true
  def description, do: "AI-powered image upscaling using Real-ESRGAN models"

  @impl true
  def input_spec do
    models = RealESRGAN.available_models()

    model_options =
      Enum.map(models, fn {key, info} ->
        %{value: key, label: info.label}
      end)

    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Input image to upscale"
      },
      model: %{
        type: :enum,
        label: "MODEL",
        default: "realesrgan-x4plus",
        options: model_options,
        description: "AI model for upscaling (scale is determined by model)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      image: %{
        type: :image,
        label: "IMAGE",
        description: "Upscaled image"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"] || config["image"]
    model = inputs["model"] || config["model"] || "realesrgan-x4plus"

    if is_nil(image) do
      {:error, "Image input is required"}
    else
      # Get scale from model definition (each model has a fixed scale)
      scale = RealESRGAN.get_model_scale(model)
      Logger.info("Upscaling image with model=#{model}, scale=#{scale}x")
      upscale_image(image, model, scale)
    end
  rescue
    e ->
      Logger.error("UpscaleImage exception: #{inspect(e)}")
      {:error, "Failed to upscale image: #{Exception.message(e)}"}
  end

  defp upscale_image(image, model, scale) do
    # Materialize input to temp file for RealESRGAN
    case Vips.materialize_to_temp(image) do
      {:ok, input_path} ->
        # Generate output path
        temp_dir = LeaxerCore.Paths.tmp_dir()
        timestamp = System.system_time(:millisecond)
        output_path = Path.join(temp_dir, "upscaled_#{scale}x_#{timestamp}.png")

        # Upscale using Real-ESRGAN
        result =
          case RealESRGAN.upscale(input_path, output_path, model: model, scale: scale) do
            {:ok, path} ->
              # Read result as base64
              case File.read(path) do
                {:ok, binary} ->
                  base64_data = Base.encode64(binary)

                  # Get dimensions using vips
                  case Vips.identify(%{path: path}) do
                    {:ok, info} ->
                      {:ok,
                       %{
                         "image" => %{
                           data: base64_data,
                           mime_type: "image/png",
                           width: info.width,
                           height: info.height
                         }
                       }}

                    {:error, _} ->
                      {:ok,
                       %{
                         "image" => %{
                           data: base64_data,
                           mime_type: "image/png"
                         }
                       }}
                  end

                {:error, reason} ->
                  {:error, "Failed to read upscaled image: #{inspect(reason)}"}
              end

            {:error, reason} ->
              {:error, reason}
          end

        # Cleanup temp files
        unless is_path_based?(image), do: File.rm(input_path)
        File.rm(output_path)

        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp is_path_based?(%{path: _}), do: true
  defp is_path_based?(%{"path" => _}), do: true
  defp is_path_based?(_), do: false
end
