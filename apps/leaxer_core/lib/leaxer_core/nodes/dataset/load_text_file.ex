defmodule LeaxerCore.Nodes.Dataset.LoadTextFile do
  @moduledoc """
  Read text file line-by-line into a list of strings.

  This node is essential for batch prompt generation workflows,
  allowing users to load prompts from external text files.

  ## Examples

      iex> LoadTextFile.process(%{"file_path" => "/path/to/prompts.txt"}, %{})
      {:ok, %{"lines" => ["prompt 1", "prompt 2", "prompt 3"], "count" => 3}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "LoadTextFile"

  @impl true
  def label, do: "Load Text File"

  @impl true
  def category, do: "Data/File"

  @impl true
  def description, do: "Read text file line-by-line into a list of strings"

  @impl true
  def input_spec do
    %{
      file_path: %{
        type: :string,
        label: "FILE PATH",
        default: "",
        description: "Path to the text file to load"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      lines: %{
        type: {:list, :string},
        label: "LINES",
        description: "List of text lines from the file"
      },
      count: %{
        type: :integer,
        label: "COUNT",
        description: "Number of lines loaded"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    file_path = inputs["file_path"] || config["file_path"] || ""

    if file_path == "" do
      {:error, "File path is required"}
    else
      load_file(file_path)
    end
  rescue
    e ->
      Logger.error("LoadTextFile exception: #{inspect(e)}")
      {:error, "Failed to load file: #{Exception.message(e)}"}
  end

  defp load_file(file_path) do
    cond do
      !File.exists?(file_path) ->
        {:error, "File not found: #{file_path}"}

      !File.regular?(file_path) ->
        {:error, "Not a regular file: #{file_path}"}

      true ->
        lines =
          File.stream!(file_path)
          |> Stream.map(&String.trim/1)
          |> Enum.to_list()

        {:ok,
         %{
           "lines" => lines,
           "count" => length(lines)
         }}
    end
  rescue
    e ->
      {:error, "Failed to read file: #{Exception.message(e)}"}
  end
end
