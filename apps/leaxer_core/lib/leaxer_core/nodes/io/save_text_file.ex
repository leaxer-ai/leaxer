defmodule LeaxerCore.Nodes.IO.SaveTextFile do
  @moduledoc """
  Save text content to file with auto-numbering.

  Essential for exporting generated prompts, captions, or metadata.

  ## Examples

      iex> SaveTextFile.process(%{"text" => "content", "filename" => "output.txt"}, %{})
      {:ok, %{"path" => "/path/to/output.txt"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  alias LeaxerCore.Security.PathValidator

  @impl true
  def type, do: "SaveTextFile"

  @impl true
  def label, do: "Save Text File"

  @impl true
  def category, do: "IO/File"

  @impl true
  def description, do: "Save text content to file with auto-numbering"

  @impl true
  def input_spec do
    %{
      text: %{
        type: :string,
        label: "TEXT",
        description: "Text content to save"
      },
      filename: %{
        type: :string,
        label: "FILENAME",
        default: "output.txt",
        description: "Output filename"
      },
      directory: %{
        type: :string,
        label: "DIRECTORY",
        default: "",
        optional: true,
        description: "Output directory (defaults to outputs/text)"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      path: %{
        type: :string,
        label: "PATH",
        description: "Path to saved file"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    text = inputs["text"] || config["text"] || ""
    raw_filename = inputs["filename"] || config["filename"] || "output.txt"
    directory = inputs["directory"] || config["directory"] || default_directory()

    cond do
      text == "" ->
        {:error, "Text content is required"}

      true ->
        # Sanitize filename to prevent path traversal attacks
        case PathValidator.sanitize_filename(raw_filename) do
          {:error, _, reason} ->
            {:error, "Invalid filename: #{reason}"}

          filename ->
            # Validate directory is within allowed outputs directory
            outputs_base = LeaxerCore.Paths.outputs_dir()

            case PathValidator.validate_within_directory(directory, outputs_base) do
              :ok ->
                save_file(text, filename, directory)

              {:error, :path_traversal, _} ->
                {:error, "Directory must be within outputs folder"}
            end
        end
    end
  rescue
    e ->
      Logger.error("SaveTextFile exception: #{inspect(e)}")
      {:error, "Failed to save file: #{Exception.message(e)}"}
  end

  defp default_directory do
    Path.join([LeaxerCore.Paths.outputs_dir(), "text"])
  end

  defp save_file(text, filename, directory) do
    # Ensure directory exists
    File.mkdir_p!(directory)

    # Generate unique filename if file exists
    output_path = generate_unique_path(directory, filename)

    # Write file
    File.write!(output_path, text)

    {:ok, %{"path" => output_path}}
  rescue
    e ->
      {:error, "Failed to write file: #{Exception.message(e)}"}
  end

  defp generate_unique_path(directory, filename) do
    base_path = Path.join(directory, filename)

    if File.exists?(base_path) do
      # Add counter to filename: output.txt -> output_1.txt, output_2.txt, etc.
      {name, ext} = split_filename(filename)
      find_unique_name(directory, name, ext, 1)
    else
      base_path
    end
  end

  defp find_unique_name(directory, name, ext, counter) do
    new_filename = "#{name}_#{counter}#{ext}"
    path = Path.join(directory, new_filename)

    if File.exists?(path) do
      find_unique_name(directory, name, ext, counter + 1)
    else
      path
    end
  end

  defp split_filename(filename) do
    case Path.extname(filename) do
      "" -> {filename, ""}
      ext -> {Path.rootname(filename), ext}
    end
  end
end
