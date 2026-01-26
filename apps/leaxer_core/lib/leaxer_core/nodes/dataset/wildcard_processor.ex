defmodule LeaxerCore.Nodes.Dataset.WildcardProcessor do
  @moduledoc """
  Replace {wildcard} syntax with random selections from files.

  Industry-standard from Automatic1111, expected by users for batch prompt generation.
  Supports patterns like:
  - {color} → reads wildcards/color.txt → selects random line
  - {animal/{type}} → supports nested paths

  ## Examples

      iex> WildcardProcessor.process(%{"template" => "a {color} cat"}, %{"wildcards_dir" => "wildcards/"})
      {:ok, %{"result" => "a blue cat"}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "WildcardProcessor"

  @impl true
  def label, do: "Wildcard Processor"

  @impl true
  def category, do: "Data/Prompt"

  @impl true
  def description, do: "Replace {wildcard} syntax with random selections from files"

  @impl true
  def input_spec do
    %{
      template: %{
        type: :string,
        label: "TEMPLATE",
        default: "",
        description: "Text with {wildcard} patterns"
      },
      wildcards_dir: %{
        type: :string,
        label: "WILDCARDS DIR",
        default: "wildcards",
        description: "Directory containing wildcard .txt files"
      },
      seed: %{
        type: :integer,
        label: "SEED",
        default: nil,
        optional: true,
        description: "Optional random seed for reproducibility"
      }
    }
  end

  @impl true
  def output_spec do
    %{
      result: %{
        type: :string,
        label: "RESULT",
        description: "Processed text with wildcards replaced"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    template = inputs["template"] || config["template"] || ""
    wildcards_dir = inputs["wildcards_dir"] || config["wildcards_dir"] || "wildcards"
    seed = inputs["seed"] || config["seed"]

    if template == "" do
      {:error, "Template is required"}
    else
      process_wildcards(template, wildcards_dir, seed)
    end
  rescue
    e ->
      Logger.error("WildcardProcessor exception: #{inspect(e)}")
      {:error, "Failed to process wildcards: #{Exception.message(e)}"}
  end

  defp process_wildcards(template, wildcards_dir, seed) do
    # Initialize random seed if provided
    if is_integer(seed) do
      :rand.seed(:exsplus, {seed, seed * 2, seed * 3})
    end

    # Find all {wildcard} patterns
    pattern = ~r/\{([^}]+)\}/

    result =
      Regex.replace(pattern, template, fn _, wildcard_name ->
        case load_wildcard(wildcards_dir, wildcard_name) do
          {:ok, lines} ->
            # Select random line
            index = :rand.uniform(length(lines)) - 1
            Enum.at(lines, index)

          {:error, reason} ->
            Logger.warning("Wildcard '#{wildcard_name}' failed: #{reason}")
            # Keep original if failed
            "{#{wildcard_name}}"
        end
      end)

    {:ok, %{"result" => result}}
  end

  defp load_wildcard(base_dir, wildcard_name) do
    # Support both "color" and "color.txt" formats
    filename =
      if String.ends_with?(wildcard_name, ".txt") do
        wildcard_name
      else
        "#{wildcard_name}.txt"
      end

    # Build full path (support nested: animal/cats)
    file_path = Path.join(base_dir, filename)

    cond do
      !File.exists?(file_path) ->
        {:error, "Wildcard file not found: #{file_path}"}

      !File.regular?(file_path) ->
        {:error, "Not a regular file: #{file_path}"}

      true ->
        lines =
          File.stream!(file_path)
          |> Stream.map(&String.trim/1)
          # Skip empty lines and comments
          |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
          |> Enum.to_list()

        if lines == [] do
          {:error, "Wildcard file is empty: #{file_path}"}
        else
          {:ok, lines}
        end
    end
  rescue
    e ->
      {:error, "Failed to load wildcard: #{Exception.message(e)}"}
  end
end
