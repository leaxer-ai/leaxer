defmodule LeaxerCore.Nodes.Dataset.RandomLineFromList do
  @moduledoc """
  Select random line from a text list with optional seed.

  Essential for generating variations by randomly selecting
  prompts from a library.

  ## Examples

      iex> RandomLineFromList.process(%{"lines" => ["a", "b", "c"]}, %{})
      {:ok, %{"text" => "b", "index" => 1}}
  """

  use LeaxerCore.Nodes.Behaviour
  require Logger

  @impl true
  def type, do: "RandomLineFromList"

  @impl true
  def label, do: "Random Line From List"

  @impl true
  def category, do: "Data/List"

  @impl true
  def description, do: "Select random line from text list with optional seed"

  @impl true
  def input_spec do
    %{
      lines: %{
        type: {:list, :string},
        label: "LINES",
        description: "List of text lines to choose from"
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
      text: %{
        type: :string,
        label: "TEXT",
        description: "Selected text line"
      },
      index: %{
        type: :integer,
        label: "INDEX",
        description: "Index of selected line (0-based)"
      }
    }
  end

  @impl true
  def process(inputs, config) do
    lines = inputs["lines"] || config["lines"] || []
    seed = inputs["seed"] || config["seed"]

    if lines == [] or not is_list(lines) do
      {:error, "Lines input must be a non-empty list"}
    else
      select_random(lines, seed)
    end
  rescue
    e ->
      Logger.error("RandomLineFromList exception: #{inspect(e)}")
      {:error, "Failed to select random line: #{Exception.message(e)}"}
  end

  defp select_random(lines, seed) when is_integer(seed) do
    # Use seeded random for reproducibility
    :rand.seed(:exsplus, {seed, seed * 2, seed * 3})
    index = :rand.uniform(length(lines)) - 1
    text = Enum.at(lines, index)

    {:ok,
     %{
       "text" => text,
       "index" => index
     }}
  end

  defp select_random(lines, _seed) do
    # Use unseeded random
    index = :rand.uniform(length(lines)) - 1
    text = Enum.at(lines, index)

    {:ok,
     %{
       "text" => text,
       "index" => index
     }}
  end
end
