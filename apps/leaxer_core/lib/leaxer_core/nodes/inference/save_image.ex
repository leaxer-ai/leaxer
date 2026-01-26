defmodule LeaxerCore.Nodes.Inference.SaveImage do
  @moduledoc """
  Save an image to disk.

  This node saves the generated image to the outputs directory with a customizable filename.
  """

  use LeaxerCore.Nodes.Behaviour

  @impl true
  def type, do: "SaveImage"

  @impl true
  def label, do: "Save Image"

  @impl true
  def category, do: "IO/Image"

  @impl true
  def description, do: "Save an image to the outputs directory"

  @impl true
  def input_spec do
    %{
      image: %{type: :image, label: "IMAGE"},
      filename_prefix: %{type: :string, label: "FILENAME PREFIX", default: "output"},
      format: %{
        type: :enum,
        label: "FORMAT",
        default: "png",
        options: [
          %{value: "png", label: "PNG"},
          %{value: "jpg", label: "JPEG"},
          %{value: "webp", label: "WebP"}
        ]
      }
    }
  end

  @impl true
  def output_spec do
    %{
      saved_path: %{type: :string, label: "SAVED PATH"}
    }
  end

  @impl true
  def process(inputs, config) do
    image = inputs["image"]
    prefix = inputs["filename_prefix"] || config["filename_prefix"] || "output"
    format = inputs["format"] || config["format"] || "png"

    # Generate output path
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    filename = "#{prefix}_#{timestamp}_#{random}.#{format}"

    output_dir = LeaxerCore.Paths.outputs_dir()
    File.mkdir_p!(output_dir)
    output_path = Path.join(output_dir, filename)

    # Check for base64 data format first (from stream_base64 mode)
    case LeaxerCore.Image.extract_base64_data(image) do
      {data, _mime_type} when is_binary(data) ->
        # Write base64 data directly to disk
        case Base.decode64(data) do
          {:ok, binary_data} ->
            case File.write(output_path, binary_data) do
              :ok ->
                {:ok, %{"saved_path" => output_path}}

              {:error, reason} ->
                {:error, "Failed to save image: #{inspect(reason)}"}
            end

          :error ->
            {:error, "Invalid base64 image data"}
        end

      nil ->
        # Fallback to path-based handling
        source_path = LeaxerCore.Image.extract_path(image)

        case source_path do
          nil ->
            {:error, "No image input provided or invalid image format"}

          path when is_binary(path) ->
            if File.exists?(path) do
              # If source and format match, just copy; otherwise we'd need conversion
              # For now, we just copy the file (sd.cpp outputs PNG)
              case File.cp(path, output_path) do
                :ok ->
                  {:ok, %{"saved_path" => output_path}}

                {:error, reason} ->
                  {:error, "Failed to save image: #{inspect(reason)}"}
              end
            else
              {:error, "Source image file not found: #{path}"}
            end
        end
    end
  end
end
