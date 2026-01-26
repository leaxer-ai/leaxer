defmodule LeaxerCore.Nodes.IO.BatchRename do
  @moduledoc """
  Rename files in directory with pattern.

  Organize 100+ generated images with meaningful names.
  Pattern variables: {name}, {counter}, {date}, {time}, {seed}

  ## Examples

      iex> BatchRename.process(%{"directory" => "/path/to/images", "pattern" => "img_{counter}.png"}, %{})
      {:ok, %{"count" => 42}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "BatchRename"

  @impl true
  def label, do: "Batch Rename"

  @impl true
  def category, do: "IO/File"

  @impl true
  def description, do: "Rename files in directory with pattern"

  @impl true
  def input_spec do
    %{
      directory: %{
        type: :string,
        label: "DIRECTORY",
        description: "Directory containing files to rename"
      },
      pattern: %{
        type: :string,
        label: "PATTERN",
        default: "{name}_{counter}{ext}",
        description: "Naming pattern with variables: {name}, {counter}, {date}, {time}, {ext}"
      },
      extension: %{
        type: :string,
        label: "EXTENSION",
        default: "",
        optional: true,
        description: "Only rename files with this extension (e.g., .png)"
      },
      start_index: %{
        type: :integer,
        label: "START INDEX",
        default: 1,
        optional: true,
        description: "Starting counter value"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      count: %{
        type: :integer,
        label: "COUNT",
        description: "Number of files renamed"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    directory = inputs["directory"] || config["directory"]
    pattern = inputs["pattern"] || config["pattern"] || "{name}_{counter}{ext}"
    extension = inputs["extension"] || config["extension"] || ""
    start_index = inputs["start_index"] || config["start_index"] || 1

    cond do
      !directory ->
        {:error, "Directory is required"}

      !File.dir?(directory) ->
        {:error, "Directory not found: #{directory}"}

      true ->
        rename_files(directory, pattern, extension, start_index)
    end
  rescue
    e ->
      Logger.error("BatchRename exception: #{inspect(e)}")
      {:error, "Failed to rename files: #{Exception.message(e)}"}
  end

  defp rename_files(directory, pattern, extension_filter, start_index) do
    files =
      File.ls!(directory)
      |> Enum.filter(fn file ->
        full_path = Path.join(directory, file)

        File.regular?(full_path) and
          (extension_filter == "" or String.ends_with?(file, extension_filter))
      end)
      |> Enum.sort()

    count =
      files
      |> Enum.with_index(start_index)
      |> Enum.reduce(0, fn {file, index}, acc ->
        old_path = Path.join(directory, file)
        new_name = apply_pattern(pattern, file, index)
        new_path = Path.join(directory, new_name)

        # Skip if names are the same
        if old_path != new_path do
          # Ensure we don't overwrite existing files
          final_path = ensure_unique(new_path)
          File.rename!(old_path, final_path)
          acc + 1
        else
          acc
        end
      end)

    {:ok, %{"count" => count}}
  end

  defp apply_pattern(pattern, filename, counter) do
    name = Path.rootname(filename)
    ext = Path.extname(filename)
    date = Date.utc_today() |> Date.to_string()
    time = Time.utc_now() |> Time.to_string() |> String.replace(":", "-")

    pattern
    |> String.replace("{name}", name)
    |> String.replace("{counter}", to_string(counter))
    |> String.replace("{date}", date)
    |> String.replace("{time}", time)
    |> String.replace("{ext}", ext)
  end

  defp ensure_unique(path) do
    if File.exists?(path) do
      dir = Path.dirname(path)
      name = Path.basename(path, Path.extname(path))
      ext = Path.extname(path)
      find_unique(dir, name, ext, 1)
    else
      path
    end
  end

  defp find_unique(dir, name, ext, counter) do
    new_path = Path.join(dir, "#{name}_#{counter}#{ext}")

    if File.exists?(new_path) do
      find_unique(dir, name, ext, counter + 1)
    else
      new_path
    end
  end
end
