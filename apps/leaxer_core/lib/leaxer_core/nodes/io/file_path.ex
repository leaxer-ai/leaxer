defmodule LeaxerCore.Nodes.IO.FilePath do
  @moduledoc """
  File picker UI returning absolute path.

  No more "where did I save that file?" errors.
  Full file picker UI will be implemented in React frontend using Tauri dialog API.

  ## Examples

      iex> FilePath.process(%{}, %{"path" => "/path/to/file.txt"})
      {:ok, %{"path" => "/path/to/file.txt"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "FilePath"

  @impl true
  def label, do: "File Path"

  @impl true
  def category, do: "IO/File"

  @impl true
  def description, do: "File picker UI returning absolute path"

  @impl true
  def input_spec do
    %{
      path: %{
        type: :string,
        label: "PATH",
        default: "",
        description: "File path (use picker button in UI)"
      },
      filter: %{
        type: :enum,
        label: "FILTER",
        default: "any",
        options: [
          %{value: "any", label: "Any"},
          %{value: "images", label: "Images"},
          %{value: "text", label: "Text Files"},
          %{value: "models", label: "Model Files"}
        ],
        description: "File type filter"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      path: %{
        type: :string,
        label: "PATH",
        description: "Absolute file path"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    path = inputs["path"] || config["path"] || ""

    if path == "" do
      {:error, "File path is required - use file picker in UI"}
    else
      {:ok, %{"path" => path}}
    end
  end
end
