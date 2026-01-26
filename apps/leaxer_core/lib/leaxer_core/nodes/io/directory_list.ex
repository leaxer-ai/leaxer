defmodule LeaxerCore.Nodes.IO.DirectoryList do
  @moduledoc """
  List files in directory with filtering.

  Essential for loading batches of images for processing.

  ## Examples

      iex> DirectoryList.process(%{"directory" => "/path/to/images", "extension" => ".png"}, %{})
      {:ok, %{"files" => ["/path/to/images/img1.png", "/path/to/images/img2.png"], "count" => 2}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "DirectoryList"

  @impl true
  def label, do: "Directory List"

  @impl true
  def category, do: "IO/File"

  @impl true
  def description, do: "List files in directory with filtering"

  @impl true
  def input_spec do
    %{
      directory: %{
        type: :string,
        label: "DIRECTORY",
        description: "Directory to list files from"
      },
      extension: %{
        type: :string,
        label: "EXTENSION",
        default: "",
        optional: true,
        description: "Filter by extension (e.g., .png, .txt)"
      },
      recursive: %{
        type: :boolean,
        label: "RECURSIVE",
        default: false,
        optional: true,
        description: "Search subdirectories"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      files: %{
        type: {:list, :string},
        label: "FILES",
        description: "List of file paths"
      },
      count: %{
        type: :integer,
        label: "COUNT",
        description: "Number of files found"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    directory = inputs["directory"] || config["directory"]
    extension = inputs["extension"] || config["extension"] || ""
    recursive = inputs["recursive"] || config["recursive"] || false

    cond do
      !directory ->
        {:error, "Directory is required"}

      !File.dir?(directory) ->
        {:error, "Directory not found: #{directory}"}

      true ->
        list_files(directory, extension, recursive)
    end
  rescue
    e ->
      Logger.error("DirectoryList exception: #{inspect(e)}")
      {:error, "Failed to list directory: #{Exception.message(e)}"}
  end

  defp list_files(directory, extension, recursive) do
    pattern =
      if recursive do
        Path.join([directory, "**", "*#{extension}"])
      else
        Path.join(directory, "*#{extension}")
      end

    files =
      Path.wildcard(pattern)
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    {:ok,
     %{
       "files" => files,
       "count" => length(files)
     }}
  end
end
